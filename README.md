# Well Water Level Monitoring (TL-136 + ESP8266/ESP32 + ESPHome)

Monitor a well (e.g. heat-pump supply) with a 4-20 mA TL-136 submersible pressure sensor and an
ESP8266 D1 mini running ESPHome. Data flows into Home Assistant for visualization, alerts, and
level-based automation (e.g. heat pump interlocks). Designed for reliability, easy calibration, and
low long-term power drain.

## Table of Contents
- [Overview](#overview)
- [Hardware Setup](#hardware-setup)
- [Software](#software)
- [Configuration](#configuration)
- [Diagnostics & Entities](#diagnostics--entities)
- [Reference](#reference)
- [License](#license)

---

## Overview

- Purpose: reliable well water level tracking with low power usage.
- Power-saving: deep sleep by default, with **awake time minimized to a short burst per cycle**.
- Deep-sleep control:
  - The device only enters deep sleep from a script (`check_deep_sleep`) via `deep_sleep.enter`.
  - Sleep duration is derived from the `cfg_sleep_duration_min` number entity (minutes, set in HA).
  - Deep sleep is **skipped** whenever:
    - `Stay Awake` is ON (`switch.deep_sleep_disable`), or
    - the Home Assistant helper `input_boolean.prevent_deep_sleep` is ON (mirrored as internal
      `binary_sensor.ha_prevent_deep_sleep`).
- Standard measurement burst + single publish:
  - On boot:
    - Short 2 s delay.
    - Wait until the ESPHome API is connected (so HA helpers are available).
    - Another 1 s delay, then the standardized measurement cycle is started via `run_measurement_cycle`.
  - During `run_measurement_cycle`:
    - `sensor_power` relay is turned ON.
    - 3 s warm-up time for sensor and EMA filter.
    - `publish_ready` is set to `false` while samples are collected.
    - A **5 s high-rate sampling loop** executes every 500 ms (~2 Hz, 10 samples):
      - `shunt_adc_raw.update()`
      - `loop_current_raw.update()`
      - `loop_current_filtered.update()`
    - After the loop:
      - Internal template sensors `sensor_column_filtered_m` and `well_depth_raw` are updated once.
      - `publish_ready` is set to `true`.
      - Diagnostics (`shunt_voltage`, `loop_current_raw`, `loop_current_filtered`) are updated.
      - Final user-facing depth entities are updated once:
        - `water_depth_from_head`
        - `water_depth_from_surface`
        - `water_over_pump1`
        - `water_over_pump2`
      - A short 1 s delay allows values to be transmitted to HA.
    - Finally, `check_deep_sleep` decides whether to schedule another cycle or enter deep sleep.
- Publish gating:
  - User-facing depth sensors (`water_depth_from_head`, `water_depth_from_surface`,
    `water_over_pump1`, `water_over_pump2`) **return `NaN` until `publish_ready` is true**, so HA only
    sees one clean “final” value per wake cycle.
- Filtering:
  - The loop current is filtered with an **exponential moving average (EMA)** plus a short warmup
    phase that discards initial samples.
  - The published depth is computed directly from the filtered loop current via a two-point
    calibration; there is no additional 5-sample ring buffer any more.
- Power optimization:
  - Sensor power is controlled by a relay; it is ON for the warm-up + sampling + publishing period.
  - If deep sleep is allowed, `check_deep_sleep`:
    - waits 10 s (grace period with sensor still ON),
    - turns `sensor_power` OFF,
    - waits another 2 s,
    - then calls `deep_sleep.enter` with the configured sleep duration.
- Maintenance & diagnostics modes:
  - **Stay Awake**: prevents deep sleep and auto-turns off after 10 minutes.
  - **Prevent deep sleep (HA helper)**: `input_boolean.prevent_deep_sleep` in HA mirrors into an
    internal binary sensor and also prevents deep sleep as long as it’s ON.
  - **Step-response debug**: a dedicated button runs a synthetic step-response test, computes timing
    and noise metrics, and then resumes the normal measurement cycle.

Typical awake timing per cycle (excluding Wi-Fi connect time):
- ~2 s (boot delay) + API wait + 1 s + 3 s (warm-up) + 5 s (burst) + 1 s (post-publish delay)
  + 10 s (grace period) + 2 s (after relay off)
- ⇒ **roughly 20–25 s** awake per cycle, with the sensor relay ON for most of that period and OFF
  for the entire deep-sleep interval.

<p align="center">
  <img src="installation.PNG" alt="Well geometry and reference depths (cfg_* and water_* entities)" width="600">
</p>

What you get
- Sensor power only when needed (relay switches the 24 V supply)
- Two-point linear calibration (mA → depth), with robust fallback
- Exponential moving average for loop current → calibrated, single-shot depth per cycle
- User-facing level entities plus diagnostics for troubleshooting
- Optional **step-response debug** mode for tuning the filter and verifying dynamic behavior

Quick start (5 steps)
1) Assemble hardware (choose wiring option) and share grounds as indicated.  
2) Create `secrets.yaml` with Wi-Fi (and optional `ota_password`).  
3) Run local validation scripts to catch issues early.  
4) Add `waterlevel-sensor.yaml` in ESPHome; flash via USB once, then OTA.  
5) In Home Assistant, set geometry, shunt value, filter window, then perform two-point calibration.

---

## Hardware Setup

Core parts

> **Important (ESP8266 only):** For deep sleep wake-up to work as specified on ESP8266 boards, you **must** connect ("short") GPIO16 (D0) to the RESET (RST) pin. Without this connection, the ESP8266 cannot wake itself from deep sleep.

- Sensor: TL-136, 0-5 m, 4-20 mA, 24 V  
- Controller: ESP8266 D1 mini (ESPHome)  
- Relay: 1-channel 5 V module (switches +24 V to the sensor or the 5 V feed to the boost)  
- Shunt: 150 Ω (≥0.25 W) in return path (loop current → voltage)  
- Power: 24 V (sensor) and 5 V (ESP + relay)

High-side switching (DEFAULT)
- Relay disconnects the 5 V feed going into the 24 V boost converter (or directly the +24 V sensor line
  if using a fixed 24 V supply).
- Result: when off, the converter + sensor draw virtually zero current; ADC reference remains solid
  because grounds stay tied.
- Recommended for stability and clean measurements.

Quick wiring (high-side 5 V feed)
```text
5V supply → Relay COM → Relay NO → Boost Vin+ → Boost 24V+ → Sensor (+)
Sensor (−) → Shunt (150 Ω) → 24V GND → MCU GND
A0 ← measurement point (top of shunt) through mandatory 1 kΩ series resistor
Relay module: IN ← D5 (GPIO14), VCC ← 5V supply, GND ← MCU GND
Optional: 100 nF–1 µF from measurement point to GND (analog low-pass)
```

Series protection & filtering (now mandatory)
- 1 kΩ series resistor before A0 (overvoltage & transient protection)  
- 100 nF–1 µF capacitor measurement point → GND (noise reduction)

Alternative wiring (low-side switching)
- Relay opens the negative/ground path of the boost converter.
- Pros: eliminates even the boost converter’s quiescent draw.
- Cons: floating measurement node when open → requires pulldown + filtering, slightly higher risk of noise.

Low-side additional parts
- Add 470 kΩ–1 MΩ pulldown from measurement node to MCU GND.
- Keep the same 1 kΩ series resistor and 100 nF–1 µF capacitor.

Full diagrams are in [ASCII Wiring Diagrams](#ascii-wiring-diagrams).

---

## Software

ESPHome device: `waterlevel-sensor.yaml` (ESP8266 D1 mini)

### Local testing (before flashing)

Windows (PowerShell)
```powershell
./scripts/test-local.ps1
```

Linux/macOS (Bash)
```bash
chmod +x scripts/test-local.sh
./scripts/test-local.sh
```

These scripts lint Markdown/YAML, validate the ESPHome configuration, and can compile firmware. Ensure a
`secrets.yaml` exists (see below).

### Build & flash
1) Add the YAML to your ESPHome dashboard.  
2) First flash via USB; subsequent updates use OTA.  
3) For CI releases, tags trigger packaging in GitHub Actions (optional).

Minimal secrets.yaml

```yaml
wifi_ssid: "YourNetworkName"
wifi_password: "YourPassword"
ap_password: "APFallbackPassword"
# If configured in YAML: ota_password: "YourOTAPassword"
```

---

## Configuration

All parameters appear as Home Assistant `number` entities (`entity_category: config`). Values
persist across deep sleep.

- Geometry numbers:  
  `cfg_surface_to_well_head` (surface ↓ head, positive),  
  `cfg_head_to_sensor`,  
  `cfg_head_to_pump1`,  
  `cfg_head_to_pump2`
- Filtering window (s): `cfg_filter_window_s` (EMA window for loop current)
- Calibration points: `cfg_cal1_*`, `cfg_cal2_*` (currents + depths)
- Shunt resistance (Ω): `cfg_shunt_resistance_ohm`
- Sensor span (m): `cfg_sensor_span_m` (factory 5.0 m for TL-136; change when using a different
  range sensor)
- Sleep duration (min): `cfg_sleep_duration_min` (used to compute `deep_sleep.enter` duration)
- Dry-detection threshold: `cfg_dry_current_band_mA` (loop current below this at publish ⇒ "waterlevel below minimum")

Depth semantics
- **Depth Below Head** (`water_depth_from_head`) is distance from the well head downward to the
  current water surface.
- **Depth Below Surface** (`water_depth_from_surface`) = Depth Below Head + Surface→Head (the fixed
  offset `cfg_surface_to_well_head`).
- Positive values mean the water surface lies below the reference (head or ground surface).  
- Invalid / unavailable readings publish as no value (NaN).

## Calibration (Quick Guide)

### Collecting Measurements (Before Calibration)

Gather these physical measurements once; they define geometry and feed calibration:

1. **Surface → Well Head** (`cfg_surface_to_well_head`):  
   Vertical distance from ground surface down to the well head (positive; e.g. 1.00 m if head is 1 m
   below surface).
2. **Well Head → Sensor** (`cfg_head_to_sensor`):  
   Distance from the well head down to the sensor position.
3. **Well Head → Pump(s)** (`cfg_head_to_pump1`, `cfg_head_to_pump2`):  
   Depth of pumps below head (for “water over pump” entities).

### Two-point Calibration

Concept:
- Use two static water levels and their corresponding loop currents to define a line:
  - Point 1: depth `d1` (from head) and current `I1`.
  - Point 2: depth `d2` (from head) and current `I2`.
- From this, the code derives a slope/intercept mapping current → depth.

Typical choice:
- **Point 1**: sensor completely dry / just at water surface (e.g. Depth from head where sensor
  starts to see water, or a known shallow level).
- **Point 2**: a deeper, stable level within 1–6 m span.

Defect / disconnect detection
- Readings with loop current below the valid range are treated as invalid; the template code uses
  a cutoff of about **3.9 mA** as "too low" to be a valid 4-20 mA signal.
- When currents are invalid, user-facing level sensors publish no value (suppressed as NaN).

### Filtering & Warmup

Loop current (`loop_current_filtered`) uses an exponential moving average:

```text
avg = avg + alpha * (raw - avg)
alpha = dt / window_s     (dt = update period)
```

- `cfg_filter_window_s` controls the smoothing window (seconds).
- A short warmup phase discards the first few EMA samples to avoid skewed initial values; during
  warmup the filtered current reports `NaN`.

Depth calculation:
- `well_depth_raw` computes calibrated "Depth Below Head (Raw)" from the **filtered** loop current,
  using the two-point calibration if valid, otherwise a fallback sensor-span curve.
- The published depth (`water_depth_from_head`) simply returns the calibrated depth once per cycle,
  **only after** `publish_ready` becomes true, so HA sees a single, smoothed depth per wake cycle.

---

## Deep Sleep & Burst Behavior

Deep sleep
- Typical cycle: wake → standardized measurement → single publish → optional delay → deep sleep.
- Sleep duration is **dynamic**:
  - `check_deep_sleep` calls `deep_sleep.enter` with  
    `sleep_duration = cfg_sleep_duration_min * 60 * 1000 ms`.
  - If `cfg_sleep_duration_min` is invalid or <1, a safety default of 10 min is used.
- Deep sleep is **only** entered from this script; there are no fixed `run_duration` or
  `sleep_duration` values in the `deep_sleep:` block.

Standardized measurement cycle (`run_measurement_cycle`)
- Powers the sensor via `sensor_power` relay.
- Waits 3 s warm-up.
- Clears `publish_ready`.
- Collects 10 samples at 2 Hz, updating:
  - `shunt_adc_raw`
  - `loop_current_raw`
  - `loop_current_filtered`
- Updates internal derived values:
  - `sensor_column_filtered_m`
  - `well_depth_raw`
- Sets `publish_ready = true`.
- Updates diagnostics and user-facing depth entities once.
- Waits 1 s to let HA receive values, then calls `check_deep_sleep`.

Relay control & extra awake time
- In `check_deep_sleep`:
  - If either `Stay Awake` or `ha_prevent_deep_sleep` is ON:
    - Deep sleep is prevented.
    - After a 10 s delay, another `run_measurement_cycle` is started.
  - If both flags are OFF:
    - The device logs that it will enter deep sleep soon.
    - Waits 10 s (grace period with sensor still powered).
    - Turns `sensor_power` OFF.
    - Waits 2 s.
    - Calls `deep_sleep.enter(...)` with the computed sleep duration.

Stay Awake & HA helper
- **Stay Awake** (`deep_sleep_disable` switch):
  - Turning ON:
    - immediately calls `deep_sleep.prevent` on `main_deep_sleep`.
    - starts the `auto_off_stay_awake` script (10 minutes).
  - After 10 minutes, if still ON, the script logs and turns the switch OFF.
  - Turning OFF:
    - re-allows deep sleep via `deep_sleep.allow`.
- **HA Helper Prevent Deep Sleep**:
  - `binary_sensor.ha_prevent_deep_sleep` mirrors `input_boolean.prevent_deep_sleep` from HA.
  - While this helper is ON, `check_deep_sleep` will not enter deep sleep; it will instead schedule
    another measurement cycle after 10 s.

Installation checklist
1. Build hardware; share ground between 24 V and 5 V rails.  
2. Create `secrets.yaml` and validate locally (scripts above).  
3. Add `waterlevel-sensor.yaml` to ESPHome and flash.  
4. In HA, set geometry, shunt resistance, filter window, then perform calibration.  
5. Set `cfg_sleep_duration_min` to your desired interval between bursts.

---

## Diagnostics & Entities

### User-facing sensors

- `water_depth_from_head`  
  Depth Below Head – calibrated EMA-filtered depth, gated by `publish_ready`.
- `water_depth_from_surface`  
  Depth Below Surface – derived from Depth Below Head + `cfg_surface_to_well_head`.
- `water_over_pump1`  
  Water height above Pump 1 (positive = pump submerged).
- `water_over_pump2`  
  Water height above Pump 2 (positive = pump submerged).
- `loop_current_filtered`  
  Loop current (mA), EMA-filtered with warmup.

### Diagnostic (internal/advanced) entities

- `shunt_adc_raw`  
  ADC internal 0–1 V raw (A0).
- `shunt_voltage`  
  ADC × 3.2 scaling to actual shunt voltage.
- `loop_current_raw`  
  Raw loop current (mA) derived from shunt voltage.
- `sensor_column_filtered_m`  
  Filtered water column above sensor (0–`cfg_sensor_span_m`), internal helper.
- `well_depth_raw`  
  Depth Below Head (raw calibrated from filtered current); used as the core depth for publishing.

Error detection
- Very low loop currents (below ~3.9 mA) are treated as invalid signals (open loop / defect),
  and user-facing depth and “over pump” sensors publish no value (NaN).

### Switches & Binary Sensors

Switches
- `sensor_power` (Sensor Power relay)  
  Controls the high-side relay that powers the boost converter / sensor. Normally always ON while
  the device is awake; turned OFF before deep sleep.
- `deep_sleep_disable` (Stay Awake)  
  Prevents deep sleep and auto-turns off after 10 minutes.

Binary sensors
- `waterlevel_below_minimum` (Waterlevel Below Minimum, device class = `problem`)  
  Evaluated only at the final publish of a measurement cycle (when `publish_ready` is true).  
  Reports ON if the filtered loop current is below `cfg_dry_current_band_mA` at that moment.
- `ha_prevent_deep_sleep` (internal)  
  Mirrors `input_boolean.prevent_deep_sleep` from Home Assistant; used only for logic, not meant
  for dashboards.

### Step-response debug

The firmware includes a synthetic step-response test for tuning and diagnostics.

Button
- `button.trigger_step_response` (Trigger Step-response)  
  Starts `run_step_response_debug`:
  - Prevents deep sleep.
  - Powers the sensor.
  - Generates a synthetic step in loop current corresponding to a 2 m change in water level.
  - Feeds both raw and EMA-filtered paths.
  - Computes dynamic metrics:
    - t90 (time to 90 % of the step)
    - t_settle (time to settle within a narrow band)
    - noise reduction factor
    - deviations at 1/2/3 s after the step
  - Publishes per-sample debug log to the logger.
  - Populates dedicated step-response entities (see below).
  - Re-allows deep sleep and resumes the normal `run_measurement_cycle`.

Sensors
- `step_response_voltage_in` – last synthetic shunt voltage used during debug  
- `step_response_depth_unfiltered` – unfiltered depth equivalent during debug  
- `step_response_depth_filtered` – filtered depth equivalent during debug  
- `step_response_t90_s` – time to 90 % of step (seconds)  
- `step_response_t_settle_s` – settling time (seconds)  
- `step_response_noise_reduction` – noise reduction factor (unfiltered vs filtered)  
- `step_response_dev1` / `step_response_dev2` / `step_response_dev3` – deviations at 1, 2, 3 s

Text sensor
- `step_response_report` – compact JSON string summarizing the last step-response (e.g.  
  `{"t90_s":..., "t_settle_s":..., "noise_reduction":..., "dev1_m":..., ...}`)  
  Useful for copy-paste into analysis tools.

### Configuration numbers (summary)

Configuration numbers (prefix omitted in HA UI display name)
- Geometry:
  - `cfg_surface_to_well_head`
  - `cfg_head_to_sensor`
  - `cfg_head_to_pump1`
  - `cfg_head_to_pump2`
- Filtering:
  - `cfg_filter_window_s`
- Calibration:
  - `cfg_cal1_current_mA`, `cfg_cal1_depth_m`
  - `cfg_cal2_current_mA`, `cfg_cal2_depth_m`
- Electrical & span:
  - `cfg_shunt_resistance_ohm`
  - `cfg_sensor_span_m`
- Sleep & dry detection:
  - `cfg_sleep_duration_min`
  - `cfg_dry_current_band_mA` (current threshold; loop current below this at publish ⇒ "below minimum")

---

## Reference

See full configuration: `waterlevel-sensor.yaml`.

Filtering, calibration, sleep control, relay logic, dry detection, and step-response debug are
implemented via template sensors, globals, scripts, and `deep_sleep.enter` in the main file.

### ASCII Wiring Diagrams

High-side wiring (default — switching 5 V feed to boost)
```text
                            HOUSE / BASEMENT
                    ┌──────────────────────────────────────────────┐
                    │                                              │
                    │  5V SUPPLY / USB                             │
                    │      +5V ─────┐                              │
                    │               │                              │
                    │          ┌────┴───────┐                      │
                    │          │  RELAY    │ (1-ch, 5 V)           │
                    │          │  COM      │                      │
                    │          │           │                      │
                    │          │  NO ─────────────► Boost Vin+ ───► 24V+ ─── Cable 1 ───► Sensor (+)
                    │          └───────────┘                      │
                    │               │                              │
                    │              GND ────────────────────────────┬────────────────────┐
                    │                                              │                    │
                    │                                      150 Ω shunt                 │
                    │                                 (≥0.25 W)  ┌──────────┐          │
                    │                                           │          │          │
                    │  Sensor (−) ── Cable 2 ───────────────────┘          │          │
                    │                                                      ▼          │
                    │                                             Measurement node   │
                    │                                              (top of shunt)    │
                    │                                              │                 │
                    │                                             1 kΩ               │
                    │                                             │                 │
                    │                        ┌────────────────────┴───────────────┐  │
                    │                        │            ANALOG FRONTEND         │  │
                    │                        │                                    │  │
                    │                        │   1 kΩ series to A0                │  │
                    │                        │   + 100 nF–1 µF → GND              │  │
                    │                        └──────────► Measurement point → D1  │  │
                    │                                              │               │  │
                    │          D1 MINI (ESP8266)                   │               │  │
                    │                                              │               │  │
                    │     5V_in  ◄── 5V supply / USB               │               │  │
                    │     GND    ─────────────────────────┬───────┘ (shared GND)  │  │
                    │     A0   ◄──────────────────────────┘                       │  │
                    │                                                              │  │
                    │     D5 (GPIO14) ───────────────► Relay IN                    │  │
                    │     5V          ───────────────► Relay VCC                   │  │
                    │     GND         ───────────────► Relay GND                   │  │
                    └──────────────────────────────────────────────────────────────┘

                            WELL SHAFT
                    ┌──────────────────────────────────────────────┐
                    │        TL-136 LEVEL SENSOR                   │
                    │      (+)  ◄──────────── Cable 1              │
                    │      (−)  ─────────────► Cable 2             │
                    └──────────────────────────────────────────────┘
```

Low-side wiring (alternative) — click to expand in the original repo if you keep the `<details>` wrapper.
You can reuse the previous ASCII diagram; the logic here has not changed, only the firmware.

---

## License

License: See `LICENSE`.

Disclaimer: Use at your own risk. Handle higher-voltage supplies safely. Ensure waterproof integrity
of downhole cabling. Contributions welcome!

