# Medical Devices

This repository contains an ESP32-based bioimpedance measurement device and a SwiftUI iOS app that guides a lower-extremity vascular screening workflow.

The project is split into two active parts:

- `arduino/firmware/Medical_Devices.ino`: ESP32 firmware that generates the excitation signal, samples the response, computes calibrated peak-to-peak voltage, and exposes measurements over BLE.
- `ios-app/Medical devices/ContentView.swift`: SwiftUI app that connects to the ESP32, walks the user through a multi-step screening flow, records repeated captures, and produces a simple clinical screening summary.

## Project Goal

The system is designed to compare repeated electrical measurements between two matched anatomical sites, then combine that asymmetry pattern with symptoms and risk factors to support screening and referral decisions.

At a high level:

1. The ESP32 generates a carrier/reference signal and measures the analog response.
2. The firmware converts that response into a calibrated peak-to-peak value in millivolts.
3. The iPhone app requests captures over BLE.
4. The app collects three captures at a primary site and three at a comparison site.
5. The app computes inter-site difference and percent change.
6. The user adds symptoms and risk factors.
7. The app returns a screening-oriented summary such as `No Significant Asymmetry Detected`, `Asymmetry Detected`, or `Elevated Vascular Risk Pattern`.

## Repository Layout

```text
.
├── README.md
├── arduino/
│   └── firmware/
│       └── Medical_Devices.ino
└── ios-app/
    ├── Medical devices/
    │   ├── Assets.xcassets/
    │   └── ContentView.swift
    └── Medical devices.xcodeproj/
```

## Firmware Overview

The active firmware lives in `arduino/firmware/Medical_Devices.ino`.

### Hardware-facing behavior

The firmware configures:

- `GPIO25` DAC output for the sine-wave carrier
- `GPIO27` as a digital reference/sync output
- `GPIO34` as the ADC input

It builds an 8-sample sine table and uses a hardware timer to output a 10 kHz carrier. While the signal is running continuously, the firmware captures ADC samples and computes a peak-to-peak response.

### Measurement pipeline

When the firmware performs a capture, it:

1. Reads `captureSampleCount` ADC samples.
2. Tracks the minimum and maximum raw ADC counts.
3. Converts the raw peak-to-peak counts to millivolts.
4. Applies `p2pCalibrationScale` to align the reading with empirical scope measurements.
5. Stores the latest value in a rolling history buffer.
6. Publishes the result over BLE.

The firmware keeps up to five recent measurements in memory and tracks the total capture count for the current session.

### BLE design

The ESP32 advertises as:

- Device name: `MedicalDevices`
- Service UUID: `FFE0`
- Data characteristic UUID: `FFE1`
- Control characteristic UUID: `FFE2`

Control characteristic commands:

- `capture`: trigger a new measurement
- `sync`: republish the current payload
- `clear`: clear measurement history and republish an empty/reset payload

Data payload format:

```text
capture_count,latest_p2p_mv,delta_from_prev_mv,history_count,h1,h2,h3,h4,h5
```

Example meaning:

- `capture_count`: total captures taken since last clear
- `latest_p2p_mv`: most recent calibrated peak-to-peak value
- `delta_from_prev_mv`: difference from the prior capture
- `history_count`: number of valid history slots populated
- `h1...h5`: rolling recent capture history, newest first

### Serial output

The firmware also prints debug information to serial during capture, including raw sample values, minimum/maximum ADC values, uncalibrated millivolts, and calibrated millivolts.

## iOS App Overview

The iOS app is implemented directly in `ios-app/Medical devices/ContentView.swift`. The same file currently contains:

- the app entry point
- the full SwiftUI interface
- the screening workflow state
- the BLE manager
- BLE delegate implementations
- UI helper views and styles

The app connects to the ESP32 over CoreBluetooth and guides the user through a five-step workflow.

### Workflow steps

1. `Setup`
   The user is instructed to place the probes 2 inches apart at a consistent location.
2. `Baseline`
   The app collects three measurements at the primary site.
3. `Comparison`
   The app collects three measurements at the matched site on the opposite limb.
4. `Symptoms`
   The user records symptoms and vascular risk factors.
5. `Result`
   The app computes a screening summary based on asymmetry and clinical context.

### BLE app behavior

`BLEDeviceManager` is responsible for:

- starting CoreBluetooth
- scanning for the `MedicalDevices` peripheral
- connecting and discovering the `FFE0` service
- subscribing to the `FFE1` notify/read characteristic
- writing control commands to `FFE2`
- parsing the incoming comma-separated payload
- exposing connection state and latest measurement data to SwiftUI

The app supports:

- connecting to the device
- requesting a fresh capture
- refreshing the current data
- clearing device-side history
- reconnecting automatically after disconnects when connection is still desired

### Capture flow inside the app

When the user taps a capture button:

1. The app writes `capture` to the BLE control characteristic.
2. The ESP32 performs a new measurement and publishes a payload.
3. The app parses the payload into a `CapturePayload`.
4. The latest peak-to-peak value is appended to either the baseline or comparison series.
5. The UI updates the session progress and summary statistics.

### Assessment logic

The result screen uses:

- the mean of the three baseline captures
- the mean of the three comparison captures
- the percent difference between them
- symptom and risk-factor toggles

Current decision rules in the app:

- If there is a non-healing wound, the app recommends prompt clinical evaluation.
- If absolute percent difference is at least 20% and there are at least two symptoms/risk factors, the app flags an elevated vascular risk pattern.
- If absolute percent difference is at least 20% without additional context, the app flags asymmetry and recommends confirming consistency.
- Otherwise, the app reports no significant asymmetry detected in that session.

This is framed as a screening aid, not a diagnostic system.

## End-to-End Workflow

The intended end-to-end workflow is:

1. Flash `arduino/firmware/Medical_Devices.ino` to the ESP32.
2. Power the measurement hardware and verify the ESP32 is advertising as `MedicalDevices`.
3. Open the iOS app from the Xcode project.
4. Tap `Connect` in the app.
5. Place the probes at the primary site with fixed 2-inch spacing.
6. Record three primary-site measurements.
7. Move to the matched comparison site while preserving spacing and placement consistency.
8. Record three comparison-site measurements.
9. Answer the symptom and risk-factor questions.
10. Review the assessment summary and determine whether follow-up testing is warranted.

## Building And Running

### Arduino / ESP32

Open `arduino/firmware/Medical_Devices.ino` in the Arduino IDE and make sure your ESP32 board support package and BLE dependencies are installed.

Expected capabilities used by the firmware include:

- ESP32 DAC output
- ESP32 ADC input
- BLE server / service / characteristics
- hardware timer interrupt support

After flashing, open Serial Monitor at `115200` baud to inspect capture/debug output.

### iOS / Xcode

Open `ios-app/Medical devices.xcodeproj` in Xcode and run the app on an iPhone with Bluetooth support.

The project includes Bluetooth usage descriptions in the generated Info.plist settings, so iOS should prompt for Bluetooth permission when needed.

## Notes And Limitations

- The active iOS implementation is concentrated in a single Swift file. That is workable for prototyping, but it would be cleaner to split UI, BLE logic, models, and assessment logic into separate files as the project grows.
- The BLE protocol is intentionally simple and human-readable, which is convenient for debugging but not optimized for versioning or schema evolution.
- The firmware uses a hard-coded calibration scale. If the analog front end changes, that factor should be revalidated.
- The screening summary is based on simple threshold logic and should not be treated as a diagnostic conclusion.
