## 1. Establish the baseline and hardware feasibility

- [x] 1.1 After leaving explore mode, archive the completed settings/Wi-Fi change so camera-networks has a canonical base; review this dependent delta against it.
- [ ] 1.2 Validate protected macOS pairing and reads with the intended GR IIIx and signed app identity; record model, firmware, OS and pairing/relaunch behavior without secrets.
- [ ] 1.3 Exercise documented power/WLAN preparation, AP discovery, exact-network association, props/photos and one complete real-file download; record initial on/sleep/off behavior and actual stage timings.
- [ ] 1.4 Verify that releasing BLE after HTTP success leaves the AP and batch download stable; resolve any required lifecycle/spec change before promoting automatic support. Leave physical checks incomplete if hardware is unavailable.

## 2. Native Bluetooth boundaries and identity

- [x] 2.1 Add isolated protocol values/strict decoders and a fakeable BLE transport with strongly retained peripherals, serialized operations, UUID/property validation and connection-generation handling.
- [x] 2.2 Add lazy Bluetooth authorization/state handling, bounded discovery, system-connected lookup, identifier retrieval, freshness expiry and foreground/admission throttling without implicit camera connection.
- [x] 2.3 Add protected setup through macOS pairing, supported identity validation and precise errors for permission, pairing, timeout, missing protocol, unexpected states and `0x80` rejection.
- [x] 2.4 Add the independent versioned device store, last explicit target, verified identity/success distinction, network linking and Forget revisions without changing existing settings/network persistence.
- [x] 2.5 Add CoreBluetooth usage description/framework/source inclusion to both build paths and the isolated test harness; keep tests on fake BLE by default.
- [x] 2.6 Send the current Mac Computer Name to the optional Paired Device Name characteristic after protected checks, refresh on reconnect, and verify Unicode, missing/invalid names, unsupported/rejected labels and link-loss handling with fake BLE; retain physical camera-label verification as outstanding.

## 3. One BLE/Wi-Fi/HTTP connection lifecycle

- [x] 3.1 Add typed targets and preparation stages to CameraConnection, preserve Current Wi-Fi and remembered-network paths, and check Wi-Fi prerequisites before camera writes.
- [x] 3.2 Implement read/conditional power-on, AP request/readback, credential pre-read/refresh, exact-SSID observation and controlled continuation if BLE drops after the AP request.
- [x] 3.3 Supply ephemeral BLE credentials directly to the Wi-Fi join path, skip saved-password prompts, refresh at most once on rejection, and clear credentials at every terminal path.
- [x] 3.4 Extend Bluetooth-route verification with expected model/props, stable SSID, ping and valid photos; preserve existing empty-list and network-history rules.
- [x] 3.5 Separate BLE link status from library readiness; release BLE after verification and retain Wi-Fi-only session health, including after release/loss.
- [x] 3.6 Add cancel/disconnect and draining admission for non-cancellable association, retired BLE callbacks and computer sleep; prevent unintended cleanup writes or stale publication.
- [x] 3.7 Preserve two-way connection/download exclusion through setup, cancellation cleanup, disconnect and target/history management.

## 4. Main-window and Settings UX

- [x] 4.1 Replace the Wi-Fi-only selector with grouped connection targets and the current-network name available in the selector; preserve explicit Bluetooth targets across absence/relaunch.
- [x] 4.2 Add named Bluetooth states, independent Wi-Fi/readiness status and CONNECT/CANCEL/CANCELLING/DISCONNECT behavior through authoritative native snapshots/events.
- [x] 4.3 Add Bluetooth setup/discovery/access and remembered-camera management to Settings, protecting active targets and keeping camera/network Forget semantics distinct.
- [x] 4.4 Add actionable stage failures, camera On anytime/passkey guidance and explicit manual Wi-Fi fallback without silent route switching.
- [x] 4.5 Verify keyboard/screen-reader behavior, safe rendering of device names, live progress and wrapping/truncation at minimum window size and while Settings is modal.

- [x] 4.6 Refine the connection header to one line, move Find cameras next to the selector, remove repeated Wi-Fi names, and show accessible Bluetooth/Wi-Fi selector icons; verify both routes at minimum width.

## 5. Verification and support status

- [x] 5.1 Test command order and payloads, no writes for unsupported/unknown states, conditional wake/AP writes, strict credentials, timeout and rejection with injected BLE/clock boundaries.
- [x] 5.2 Test discovery without wake, system-connected versus app-connected state, stale availability, multiple cameras, remembered-but-absent targets, permission denial and initial-pairing results.
- [x] 5.3 Test BLE drop before/during/after handoff, Wi-Fi-only routes, identity mismatch, empty library, credential refresh, cancelled association drain, old callbacks and sleep invalidation.
- [x] 5.4 Test device persistence/migration, identity versus library success, secret isolation, independent Forget operations and stale history/link suppression.
- [x] 5.5 Extend real WebKit/native bridge checks for target selection, Bluetooth name/status, primary actions, cancellation locks, manual recovery and settings updates with fake radios.
- [x] 5.6 Run the existing regression suite, both build paths, strict OpenSpec validation and diff checks; keep application-code work outside explore mode.
- [x] 5.7 Update README with one-time pairing, On anytime, CONNECT behavior, retained manual access and precisely measured support/experimental limits. Record physical results separately from automated tests.
