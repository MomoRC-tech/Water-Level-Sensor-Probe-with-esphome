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

Quick wiring
- Forward: `+24V → Relay COM → Relay NO → Cable 1 → Sensor (+)`
- Return: `Sensor (–) → Cable 2 → measurement point → 150 Ω shunt → 24V‑GND`
- D1 mini: `A0 → measurement point`, `GND → 24V‑GND`, `D5(GPIO14) → Relay IN`, `5V → Relay VCC`, `GND → Relay GND`

Recommended add‑ons
- 1–2 kΩ series resistor between measurement point and A0 (input protection)
- 100 nF–1 µF capacitor from measurement point to GND (analog low‑pass)

Two wiring options (choose one)
- Low‑side switching (DEFAULT in this guide): the relay switches the 24 V “−/GND”.
	- Pros: lets you open the DC‑DC ground so the 24 V converter and sensor draw essentially zero idle power when not measuring; reduces standby consumption.
	- Cons: when the relay is open the measurement node floats; requires a pulldown and input protection to keep the ADC stable.
- High‑side switching (previous design): the relay switches `+24 V` to the sensor.
	- Pros: ADC node stays referenced to GND at all times; simplest to measure and debug; very stable.
	- Cons: the 24 V converter remains grounded and may draw small idle current even when the sensor is off.

Low‑side implementation details (default)
- Add a 470 kΩ–1 MΩ pulldown from the measurement node (relay COM / shunt top) to MCU GND.
- Keep the 1–2 kΩ series resistor to A0 and a 100 nF–1 µF capacitor from the node to GND.
- Ensure the 24 V supply `Vin−` and `Vout−` are common; MCU GND ties to that common when the relay closes.

Quick wiring (low‑side)
```text
Relay NO ("ON") → MCU GND
Relay COM → measurement node → shunt (150 Ω) → 24V Vin− (common with Vout−)
Relay COM → A0 via 1–2 kΩ; node → 100 nF–1 µF → GND; node → 470 kΩ–1 MΩ → GND
24V Vin+ ← +5 V input (DC‑DC); 24V Vout+ → Sensor (+) via Cable 1
Sensor (−) via Cable 2 → measurement node
```

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

- Geometry numbers: `ground_to_wellhead`, `head_to_sensor`, `head_to_pump1`, `head_to_pump2`, `head_to_bottom` (informational)
- Filtering window (s): `cfg_filter_window_s`
- Calibration points: `cfg_cal1_*`, `cfg_cal2_*` (currents + depths)
- Shunt resistance (Ω): `cfg_shunt_resistance_ohm`

Calibration
- Provide two known pairs: (current mA, depth m from well head).
- Validated: current delta > 0.1 mA, depth delta > 0.01 m, finite values.
- If invalid, falls back to sensor span (0–5 m column → depth by geometry).

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
## Diagnostics
User‑facing
- `water_depth_from_head`, `water_depth_from_ground`, `water_over_pump1`, `water_over_pump2`

Diagnostic entities
- `shunt_voltage` (ADC × 3.2 for D1 mini scaling)
- `loop_current_raw`, `loop_current_filtered`
- `sensor_column_filtered_m` (0–5 m column over sensor)

Error detection
- `binary_sensor.water_sensor_error` → TRUE if implausible shunt voltage (< 0.05 V or > 3.2 V). 10 s delayed ON/OFF to ignore spikes.

---
## Reference
See full configuration: `waterlevel-sensor.yaml`.

### YAML Excerpt
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
Filtering, calibration, and error logic are implemented via template sensors in the main file.

### ASCII Wiring Diagrams

Low‑side wiring (default)
```
										HOUSE / BASEMENT
					┌─────────────────────────────────────┐
					│                                     │
					│       DC‑DC 24 V BOOST (from 5 V)   │
					│                                     │
					│  Vin+  ◄───────────────  +5 V       │
					│  Vin−  ─────────────┐               │
					│  Vout+ ────────┐    │               │
					│  Vout− ─────┐  │    │  (Vin− tied to Vout−) 
					│             │  │    │
					│             │  │    └───┐
					│             │  │        │
					│             │  │     ┌──┴───┐   RELAY MODULE (1‑ch, 5 V)
					│             │  │     │ COM  │───── measurement node ──┬───── A0 (via 1–2 kΩ)
					│             │  │     │      │                         │
					│             │  │     │ NO   │───── MCU GND             │
					│             │  │     └──────┘                         │
					│             │  │                                       │
					│             │  └───[ 150 Ω shunt ]─── to 24V Vout−/Vin−┘
					│             │
					│      +24V ──┴────────────── Cable 1 ─────► Sensor (+)  │
					│                                     │                  │
					│  Cable 2 ◄────────────── Sensor (−) ◄──────────────────┘
					│
					│ Measurement node: add 470 kΩ–1 MΩ → GND and 100 nF–1 µF → GND
					│
					│          D1 MINI (ESP8266)          │
					│      5V_in  ◄── 5V supply / USB     │
					│      GND    ────────────────┐
					│      D5 (GPIO14) ─────► Relay IN    │
					│      5V          ─────► Relay VCC   │
					│      GND         ─────► Relay GND   │
					└─────────────────────────────────────┘

										WELL SHAFT
					┌─────────────────────────────────────┐
					│        TL‑136 LEVEL SENSOR          │
					│      (+)  ◄────────── Cable 1       │
					│      (−)  ───────────► Cable 2      │
					└─────────────────────────────────────┘
```

<details>
<summary>High‑side wiring (previous design) — click to expand</summary>

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
