# Well Water Level Monitoring (TL‑136 + ESP8266 + ESPHome)

Monitor a well (e.g. heat‑pump supply) with a 4–20 mA TL‑136 submersible pressure sensor and an ESP8266 D1 mini running ESPHome. Data flows into Home Assistant for visualization, alerts, and automations.

## Table of Contents
- [Overview](#overview)
- [Hardware Setup](#hardware-setup)
- [Software](#software)
- [Configuration](#configuration)
- [Diagnostics](#diagnostics)
- [Reference](#reference)
- [License](#license)

---
## Overview
- Purpose: reliable well water level tracking with low power usage.
- Power-saving: deep sleep by default (30 s active / 10 min sleep).
- OTA-friendly: deep sleep can be disabled from Home Assistant.
- Flexible setup: all geometry, calibration, and filtering are configurable from HA (no reflashing).
- Safety: error sensor flags implausible shunt voltage range.

What you get
- Sensor power only when needed (relay switches the 24 V supply)
- Two‑point linear calibration (mA → depth), with robust fallback
- Exponential moving average filtering and warmup handling
- User‑facing level entities plus diagnostics for troubleshooting

Quick start (5 steps)
1) Assemble hardware (choose wiring option) and share grounds as indicated.
2) Create `secrets.yaml` with Wi‑Fi (and optional `ota_password`).
3) Run local validation scripts to catch issues early.
4) Add `waterlevel-sensor.yaml` in ESPHome; flash via USB once, then OTA.
5) In Home Assistant, set geometry, shunt value, filter window, then perform two‑point calibration.

---
## Hardware Setup
Core parts
- Sensor: TL‑136, 0–5 m, 4–20 mA, 24 V
- Controller: ESP8266 D1 mini (ESPHome)
- Relay: 1‑channel 5 V module (switches +24 V to the sensor)
- Shunt: 150 Ω (≥0.25 W) in return path (loop current → voltage)
- Power: 24 V (sensor) and 5 V (ESP + relay)

High‑side switching (DEFAULT)
- Relay disconnects the 5 V feed going into the 24 V boost converter (or directly the +24 V sensor line if using a fixed 24 V supply).
- Result: when off, the converter + sensor draw virtually zero current; ADC reference remains solid because grounds stay tied.
- Recommended for stability and clean measurements.

Quick wiring (high‑side 5 V feed)
```text
5V supply → Relay COM → Relay NO → Boost Vin+ → Boost 24V+ → Sensor (+)
Sensor (−) → Shunt (150 Ω) → 24V GND → MCU GND
A0 ← measurement point (top of shunt) through mandatory 1 kΩ series resistor
Relay module: IN ← D5 (GPIO14), VCC ← 5V supply, GND ← MCU GND
Optional: 100 nF–1 µF from measurement point to GND (analog low‑pass)
```

Series protection & filtering (now mandatory)
- 1 kΩ series resistor before A0 (overvoltage & transient protection)
- 100 nF–1 µF capacitor measurement point → GND (noise reduction)

Alternative wiring (low‑side switching)
- Relay opens the negative/ground path of the boost converter.
- Pros: eliminates even the boost converter’s quiescent draw.
- Cons: floating measurement node when open → requires pulldown + filtering, slightly higher risk of noise.

Low‑side additional parts
- Add 470 kΩ–1 MΩ pulldown from measurement node to MCU GND.
- Keep the same 1 kΩ series resistor and 100 nF–1 µF capacitor.

Full diagrams are in [ASCII Wiring Diagrams](#ascii-wiring-diagrams).

---
## Software
ESPHome device: `waterlevel-sensor.yaml` (ESP8266 D1 mini)

Local testing (before flashing)

Windows (PowerShell)
```powershell
./scripts/test-local.ps1
```

Linux/macOS (Bash)
```bash
chmod +x scripts/test-local.sh
./scripts/test-local.sh
```

These scripts lint Markdown/YAML, validate the ESPHome configuration, and can compile firmware. Ensure a `secrets.yaml` exists (see below).

Build & flash
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
All parameters appear as Home Assistant `number` entities (`entity_category: config`). Values persist across deep sleep.

- Geometry numbers: `cfg_surface_to_well_head` (surface ↓ head, positive), `cfg_head_to_sensor`, `cfg_head_to_pump1`, `cfg_head_to_pump2`, `cfg_head_to_bottom` (informational)
- Filtering window (s): `cfg_filter_window_s`
- Calibration points: `cfg_cal1_*`, `cfg_cal2_*` (currents + depths)
- Shunt resistance (Ω): `cfg_shunt_resistance_ohm`
- Sensor span (m): `cfg_sensor_span_m` (factory 5.0 m for TL‑136; change when using a different range sensor)

Depth semantics
- "Depth Below Head" (`water_depth_from_head`) is distance from the well head downward to the current water surface.
- "Depth Below Surface" (`water_depth_from_surface`) = Depth Below Head + Surface→Head (the fixed offset `cfg_surface_to_well_head`).
- Positive values mean the water surface lies below the reference (head or ground surface). Invalid / unavailable readings publish as no value (NaN).

Calibration
- Provide two known pairs: (current mA, depth m from well head).
- Validated: current delta > 0.1 mA, depth delta > 0.01 m, finite values.
- If invalid, falls back to configured sensor span (`cfg_sensor_span_m` column → depth by geometry).

Example (factory TL‑136, span 5.0 m, sensor mounted 5.0 m below well head)
| Condition | Loop current | Water column above sensor | Depth from well head |
|-----------|--------------|---------------------------|----------------------|
| Dry (top of water at sensor) | ~4.00 mA | 0.0 m | 5.0 m (head_to_sensor) |
| Full span | ~20.00 mA | 5.0 m | 0.0 m (head_to_sensor - span) |

Set calibration point 1 to (4.00 mA, 5.0 m) and point 2 to (20.00 mA, 0.0 m), then adjust after confirming stable readings.

Defect / disconnect detection
- Readings with loop current < 4 mA (below nominal 4–20 mA range) are treated as invalid and user-facing level sensors publish no value (suppressed as NaN).

Filtering & warmup
```text
avg = avg + alpha * (raw - avg)
alpha = dt / window_s     (dt = update period)
```
Warmup suppresses the first few publishes to avoid skewed initial values.

Deep sleep
- Typical cycle: wake → energize sensor → measure → publish → power off → sleep.
- Toggle “Deep Sleep Disable” in HA to keep the device awake for OTA/debugging.

Installation checklist
1. Build hardware; share ground between 24 V and 5 V rails.
2. Create `secrets.yaml` and validate locally (scripts above).
3. Add `waterlevel-sensor.yaml` to ESPHome and flash.
4. In HA, set geometry, shunt resistance, filter window, then perform calibration.

---
## Diagnostics & Entities
User‑facing sensors
- `water_depth_from_head` (Depth Below Head)
- `water_depth_from_surface` (Depth Below Surface)
- `water_over_pump1` (Over Pump 1)
- `water_over_pump2` (Over Pump 2)
- `loop_current_filtered` (Loop Current)

Diagnostic (internal) entities
- `shunt_adc_raw` (ADC Internal 0–1 V raw)
- `shunt_voltage` (ADC × 3.2 scaling to actual shunt voltage)
- `loop_current_raw` (raw loop current mA)
- `sensor_column_filtered_m` (filtered water column above sensor)
- `loop_current_filtered` (filtered loop current, user-facing)

Error detection
- `binary_sensor.water_sensor_error` → TRUE if implausible shunt voltage (< 0.05 V or > 3.2 V). 10 s delayed ON/OFF to ignore spikes.

Switches
- `sensor_power` (Sensor Power)
- `deep_sleep_disable` (Stay Awake)

Configuration numbers (prefix omitted in HA UI display name)
- `cfg_surface_to_well_head`, `cfg_head_to_sensor`, `cfg_head_to_pump1`, `cfg_head_to_pump2`, `cfg_head_to_bottom`
- `cfg_filter_window_s`, `cfg_cal1_current_mA`, `cfg_cal1_depth_m`, `cfg_cal2_current_mA`, `cfg_cal2_depth_m`
- `cfg_shunt_resistance_ohm`, `cfg_sensor_span_m`

---
## Reference
See full configuration: `waterlevel-sensor.yaml`.

Filtering, calibration, and error logic are implemented via template sensors in the main file.

### ASCII Wiring Diagrams

High‑side wiring (default — switching 5 V feed to boost)
```
							HOUSE / BASEMENT
					┌─────────────────────────────────────┐
					│                                     │
					│  5V SUPPLY / USB                    │
					│      +5V ───┐                       │
					│             │                       │
					│         ┌───┴───────┐               │
					│         │  RELAY    │ (1‑ch, 5 V)   │
					│         │  COM      │               │
					│         │           │               │
					│         │  NO ────────────► Boost Vin+ ───► 24V+ ─── Cable 1 ───► Sensor (+)
					│         └───────────┘               │
					│             │                       │
					│            GND ─────────────────────┬───────────────┐
					│                                     │               │
					│                             150 Ω shunt             │
					│                        (≥0.25 W)  ┌───────┐         │
					│                                   │       │         │
					│  Sensor (−) ── Cable 2 ───────────┘       │         │
					│                                           ▼         │
					│                                Measurement node     │
					│                                | | 1 kΩ series → A0 │
					│                                | | 100 nF–1 µF → GND│
					│                                                GND  │
					│          D1 MINI (ESP8266)                       │  │
					│      5V_in  ◄─────────────── (same +5V)          │  │
					│      GND    ─────────────────────────────────────┘  │
					│      D5 (GPIO14) ─────► Relay IN                      │
					│      5V          ─────► Relay VCC                     │
					│      GND         ─────► Relay GND                     │
					└─────────────────────────────────────┘

							WELL SHAFT
					┌─────────────────────────────────────┐
					│        TL‑136 LEVEL SENSOR          │
					│      (+)  ◄────────── Cable 1       │
					│      (−)  ───────────► Cable 2      │
					└─────────────────────────────────────┘
```

<details>
<summary>Low‑side wiring (alternative) — click to expand</summary>

```
										HOUSE / BASEMENT
					┌─────────────────────────────────────┐
					│                                     │
					│            24V SUPPLY               │
					│                                     │
					│      +24V ──────┐                   │
					│                 │                   │
					│                 │      RELAY MODULE │
					│                 │      (1-ch, 5 V)  │
					│                 │                   │
					│             ┌───┴───────┐           │
					│             │   COM     │           │
					│             │           │           │
					│             │   NO ───────────── Cable 1 ─────► down to well
					│             │           │           │
					│             └───────────┘           │
					│                 │                   │
					│                GND ──────┐          │
					│                          │          │
					│        SHUNT 150 Ω       │          │
					│         (≥0.25 W)        │          │
					│                          │          │
					│   24V-GND ──────┤◄───[ R_shunt ]─── Cable 2 ◄──── from well
					│                          │
					│                          └───► Measurement point → D1 mini A0
					│                                     │
					│                                     │
					│          D1 MINI (ESP8266)          │
					│                                     │
					│     5V_in  ◄── 5V supply / USB      │
					│     GND    ──────────────┬──────────┘
					│                          │ (shared ground with 24V-GND)
					│     A0   ◄───────────────┘ (top end of shunt)
					│
					│     D5 (GPIO14) ─────► Relay IN
					│     5V          ─────► Relay VCC
					│     GND         ─────► Relay GND
					│
					└─────────────────────────────────────┘

										WELL SHAFT
					┌─────────────────────────────────────┐
					│                                     │
					│        TL-136 LEVEL SENSOR          │
					│                                     │
					│      (+)  ◄────────── Cable 1       │
					│      (-)  ───────────► Cable 2      │
					│                                     │
					└─────────────────────────────────────┘
```

</details>

---
## License
License: See `LICENSE`.

Disclaimer: Use at your own risk. Handle higher‑voltage supplies safely. Ensure waterproof integrity of downhole cabling. Contributions welcome!
