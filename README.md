# Well Water Level Monitoring with TL-136, ESP8266 (D1 mini) and ESPHome

Monitor a well (e.g. for a heat pump supply) using a 4–20 mA submersible pressure sensor (TL-136) and an ESP8266 D1 mini running ESPHome. Measurements are sent to Home Assistant for visualization, automation (pump protection, low level alarms, logging) and long-term analysis.

## Table of Contents
1. Goals & Features
2. Hardware Overview
3. Wiring (Quick Summary)
4. Functional Architecture (ESPHome)
5. Configurable Parameters (Home Assistant)
6. Two-Point Calibration
7. Filtering & Warmup Logic
8. Deep Sleep Behavior
9. Computed / Diagnostic Entities
10. Error Detection
11. Installation & Commissioning
12. YAML Configuration Reference
13. ASCII Wiring Diagram (Detailed)
14. Extension Ideas
15. License & Disclaimer

---
## 1. Goals & Features
**Goal:** Reliable well water level tracking with low power usage and full configuration from Home Assistant UI.

**Features:**
- Sensor power only when needed (relay control of 24 V supply)
- Full geometry and calibration configuration via HA numbers (no reflashing)
- Two-point linear calibration (mA → depth from well head) with automatic fallback to raw 0–5 m sensor span
- Exponential moving average (configurable window seconds)
- Warmup phase (first cycles suppressed → avoids distorted initial filtered value)
- Deep Sleep (default: 30 s active / 10 min sleep) for low energy
- Deep Sleep can be disabled via HA switch for OTA / debugging
- Diagnostic entities (ADC voltage, loop current raw/filtered, sensor column, error flag)
- Error binary sensor for implausible shunt voltage range

---
## 2. Hardware Overview
**Sensor:** TL-136 submersible pressure transducer (0–5 m, 4–20 mA, 24 V)
**Controller:** ESP8266 D1 mini (ESPHome)
**Relay Module:** 1-channel, 5 V (switches +24 V line to sensor)
**Shunt:** 150 Ω (≥0.25 W) in sensor return path (converts loop current to measurable voltage)
**Power Supplies:** 24 V (sensor), 5 V (ESP + relay, e.g. USB)

**Recommended addons:**
- 1–2 kΩ series resistor between measurement point and A0 (input protection)
- 100 nF–1 µF capacitor from measurement point to ground (analog low-pass)

---
## 3. Wiring (Quick Summary)
24 V supply: `+24V → Relay COM`, `Relay NO → cable (Ader 1) → Sensor (+)`
Return path: `Sensor (–) → cable (Ader 2) → measurement point → shunt (150 Ω) → 24V-GND`
D1 mini: `A0 → measurement point`, `GND → 24V-GND (shared)`, `D5(GPIO14) → Relay IN`, `5V → Relay VCC`, `GND → Relay GND`

Optional: series resistor + capacitor at measurement point for smoother readings.

---
## 4. Functional Architecture (ESPHome)
- Board: `esp8266.board: d1_mini`
- Deep sleep block: `run_duration: 30s`, `sleep_duration: 10min`
- `on_boot`: reads HA switch `deep_sleep_disable` to call `deep_sleep.prevent` or `deep_sleep.allow`
- `on_shutdown`: turns relay OFF (sensor unpowered before sleeping)
- Relay on D5 with `inverted: true` (active LOW modules). `restore_mode: ALWAYS_ON` ensures sensor is powered immediately after wake.

---
## 5. Configurable Parameters (Home Assistant)
Created as `number` entities (`entity_category: config`):
- Geometry: ground_to_wellhead, head_to_sensor, head_to_pump1, head_to_pump2, head_to_bottom (informational currently)
- Filtering window seconds: `cfg_filter_window_s`
- Calibration points: currents + depths (`cfg_cal1_*`, `cfg_cal2_*`)
- Shunt resistance: `cfg_shunt_resistance_ohm`

All adjustments survive deep sleep and reboot (restore_value).

---
## 6. Two-Point Calibration
Two known points (current mA and depth m from well head) define a linear mapping. Validation checks ensure meaningful difference (current delta >0.1 mA, depth delta >0.01 m, no NaNs). If invalid, fallback uses theoretical sensor span: sensor column (0–5 m) above sensor → depth = sensor_position − column.

Formula (valid case):
```
t = (I - I1) / (I2 - I1)
depth = D1 + t * (D2 - D1)
```

---
## 7. Filtering & Warmup Logic
Exponential moving average:
```
avg = avg + alpha * (raw - avg)
alpha = dt / window_s        # dt = sensor_update_sec
```
Warmup: first `WARMUP_SAMPLES` (3) cycles output `NAN` while internal state converges.

---
## 8. Deep Sleep Behavior
Normal cycle:
1. Wake → relay ON (sensor energized)
2. Several measurement cycles (warmup) executed
3. Filtered values published to HA
4. `on_shutdown` → relay OFF → device sleeps (sensor & coil unpowered)

Debug / OTA:
Enable HA switch “Deep Sleep Disable” → `deep_sleep.prevent`. Device remains awake. Disable the switch to re-enable sleep.

---
## 9. Computed / Diagnostic Entities (Selection)
- `shunt_voltage` – computed shunt voltage (ADC * 3.2 factor for D1 mini scaling)
- `loop_current_raw` / `loop_current_filtered` – raw vs filtered loop current (mA)
- `sensor_column_filtered_m` – filtered water column (0–5 m) over sensor (diagnostic)
- `water_depth_from_head` – water surface depth below well head (m)
- `water_depth_from_ground` – depth below ground surface
- `water_over_pump1`, `water_over_pump2` – water height over pumps (positive = submerged)

---
## 10. Error Detection
`binary_sensor.water_sensor_error` is true when sensor is powered yet shunt voltage is implausible (<0.05 V or >3.2 V). 10 s delayed ON/OFF filters transient spikes.

---
## 11. Installation & Commissioning
1. Assemble hardware; ensure common ground between 24 V and 5 V.
2. Adjust `wifi_ssid` / `wifi_password` substitutions.
3. Add `waterlevel-sensor.yaml` to ESPHome dashboard.
4. Flash via USB (initial) then OTA subsequent updates.
5. In HA, tune geometry numbers, shunt resistance, filter window.
6. Set calibration after stable readings (avoid using warmup phase values).
7. Optional: add series resistor + capacitor for noise reduction.

Calibration tip: Use known low/high water states or a reference measurement (manual probe). Record stable currents and depths before entering them.

---
## 12. YAML Configuration Reference (Excerpt)
See full file: `waterlevel-sensor.yaml`.
```yaml
deep_sleep:
	id: main_deep_sleep
	run_duration: 30s
	sleep_duration: 10min

switch:
	- platform: output
		id: sensor_power
		restore_mode: ALWAYS_ON
	- platform: template
		id: deep_sleep_disable
		turn_on_action:
			- deep_sleep.prevent: main_deep_sleep
		turn_off_action:
			- deep_sleep.allow: main_deep_sleep
```
Filtering, calibration, error logic implemented via template sensors (see file for full details).

---
## 13. ASCII Wiring Diagram (Detailed)
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
**Signal path during measurement:**
- Forward: `+24V → Relay COM → Relay NO → Cable 1 → Sensor (+)`
- Return: `Sensor (–) → Cable 2 → measurement point (top of shunt) → shunt → 24V-GND`
- D1 mini measures voltage at measurement point vs ground (scaled by shunt).
- Relay IN (D5) controls +24 V feed via COM/NO.
- 5 V powers D1 mini + relay. 24 V and 5 V share a common ground.

**Optional (recommended):**
- 1–2 kΩ series resistor between measurement point and A0
- 100 nF–1 µF capacitor measurement point to GND (analog low-pass)

---
## 14. Extension Ideas
- Adaptive `sleep_duration` when level changes rapidly
- Alerts (persistent notifications) on low/high thresholds
- Historical storage (InfluxDB / Long-Term Statistics)
- Temperature compensation (sensor drift mitigation)
- Even lower power: external logic to hard-cut 24 V supply outside measurement window

---
## 15. License & Disclaimer
License: See `LICENSE`.

Disclaimer: Use at your own risk. Mains / higher voltage supply handling only by qualified persons. Ensure safe operation of 24 V components and waterproof integrity of downhole cabling.

Contributions & improvements welcome.
