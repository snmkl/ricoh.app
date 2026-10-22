## Why

The browser currently needs the camera's Wi-Fi to be enabled before connecting. BLE research identifies a credible way to reach an off GR IIIx, enable its access point and obtain credentials; the app needs a visible camera target and one connection action that performs this handoff without confusing Bluetooth presence with a working photo connection.

## What Changes

- Add native Bluetooth discovery, remembered camera identities, protected pairing setup, power preparation, WLAN activation and credential reads using CoreBluetooth.
- Replace the Wi-Fi-only selector with one connection-target selector containing Bluetooth cameras, nearby remembered Wi-Fi networks and Current Wi-Fi. Show the current Wi-Fi name once in its selector option; use Bluetooth/Wi-Fi icons and keep Find cameras beside the selector in a single-line header.
- Show the selected or connected Ricoh's name and truthful Bluetooth state: available, remembered, connected on Mac, connecting, connected to this app, or released after handoff. Separate this from Wi-Fi association and camera-library readiness.
- Make CONNECT to a Bluetooth camera perform BLE connection, wake when required, Wi-Fi activation, association and camera verification. Provide CANCEL during preparation and DISCONNECT after success. Discovery alone never wakes a camera or switches networks.
- Remember successfully identified Bluetooth cameras independently of network history. Provide Find cameras, setup guidance, and Forget camera in Settings without removing the macOS bond or Wi-Fi history.
- Use freshly read BLE credentials in memory for the handoff. Preserve existing Wi-Fi-only credential handling and Current Wi-Fi fallback.
- Bound radio operations, retain the download/connection exclusion guard through cancellation cleanup, and reject stale callbacks across all transports.
- Keep automatic power-off, background waking, proprietary authentication guesses and firmware modification outside this change.

## Capabilities

### New Capabilities

- `camera-bluetooth`: Camera discovery and identity, explicit BLE setup, protected GATT exchange, power/WLAN preparation, transport lifetime and device history.
- `camera-connection-ui`: Unified connection targets, Bluetooth/Wi-Fi status, connect/cancel/disconnect actions and setup/recovery guidance.

### Modified Capabilities

- `camera-networks`: Extend joining and verification to BLE-derived targets and credentials; coordinate cancellation and separate BLE link loss from Wi-Fi session loss. The completed settings/Wi-Fi baseline was archived as `2026-10-21-add-settings-and-wifi-reconnect`; its canonical requirements are now in `openspec/specs/camera-networks/spec.md`.

## Impact

- New focused native Swift files for BLE protocol values, CoreBluetooth transport and camera discovery/history; extend `CameraConnection` and the existing WebKit bridge in `GRBrowser.swift`.
- Main connection controls, status rows and the Bluetooth section of the native Settings panel.
- `Info.plist`, `Makefile`, `build.sh` and the test harness for CoreBluetooth and source inclusion; keep macOS 13.3 and the existing bundle identity.
- Existing preferences remain valid; add an independent versioned camera-history record without rewriting network history or download settings.
- No third-party runtime dependency. Hardware validation of the signed macOS app is required before describing automatic wake as supported for a model/firmware combination.
- The experimental software implementation is present; physical-camera validation remains pending as recorded in `validation.md`.
