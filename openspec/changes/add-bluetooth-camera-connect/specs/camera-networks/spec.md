## MODIFIED Requirements

### Requirement: Wi-Fi selector and current network

The main connection controls SHALL expose a unified connection-target selector containing Bluetooth cameras, Current Wi-Fi and other currently available remembered camera Wi-Fi networks without duplicating the current SSID within the Wi-Fi options. The Current Wi-Fi option SHALL retain the latest network name or explicit unknown-name/disconnected state even when another route is selected. The name MUST NOT be repeated in a separate status row; the selected route SHALL have a Bluetooth or Wi-Fi icon in the compact single-line header. All remembered networks SHALL remain manageable in Settings. Explicit available Wi-Fi selections SHALL persist; disappearance or Forget SHALL fall back to Current Wi-Fi rather than another camera. Bluetooth-target persistence SHALL follow the camera-connection-ui requirements. With discovery authorized, the active app SHALL refresh remembered-network availability, pausing scans during setup/downloads. Current-network identity SHALL update independently of scans. Selecting or observing targets MUST NOT associate or contact a camera.

#### Scenario: Current Wi-Fi without history
- **WHEN** network history is empty or no remembered SSID is available
- **THEN** the unified selector retains Current Wi-Fi and the current network's name or explicit unknown/disconnected state remains visible

#### Scenario: Camera Wi-Fi appears later
- **WHEN** an authorized foreground refresh discovers a remembered camera network
- **THEN** its Wi-Fi route becomes selectable without association or an app restart

#### Scenario: Selected Wi-Fi disappears
- **WHEN** an explicitly selected remembered Wi-Fi route disappears or is forgotten
- **THEN** the app falls back to Current Wi-Fi without changing networks or silently selecting a Bluetooth camera

#### Scenario: Current identity changes during download
- **WHEN** an active download pauses scanning and the current Wi-Fi identity changes
- **THEN** a lightweight read updates the displayed current network without association or scanning

### Requirement: Join selected Wi-Fi before camera connection

For a remembered Wi-Fi target, CONNECT SHALL revalidate and join that exact available network if necessary before bounded readiness and camera verification. Current Wi-Fi SHALL use the existing network without switching. For a Bluetooth target, CONNECT SHALL prepare the selected camera AP, resolve its exact SSID from the same protected BLE attempt, join it if necessary, and verify stable network identity, expected model from camera properties, ping and a valid photo list. A valid empty photo list SHALL count as success. The app MUST NOT require internet access, silently change targets, or learn a network from failed verification. Already-joined targets SHALL skip association. BLE loss after a verified handoff MUST NOT invalidate the Wi-Fi session by itself.

#### Scenario: Existing Wi-Fi-only reconnect
- **WHEN** CONNECT targets an available remembered Wi-Fi network
- **THEN** the app retains join/readiness/ping/photo verification without BLE preparation

#### Scenario: BLE target has no AP at first
- **WHEN** BLE preparation activates an initially absent AP
- **THEN** the app waits for the exact BLE-derived SSID, associates and verifies the expected camera before displaying photos or learning a network

#### Scenario: Camera identity disagrees
- **WHEN** the Bluetooth route reaches HTTP properties identifying a different model
- **THEN** verification fails without displaying a ready library or learning the network for that attempt

#### Scenario: Already on the target SSID
- **WHEN** the current network exactly matches the selected camera's resolved SSID
- **THEN** the app skips reassociation and password lookup and performs camera verification

### Requirement: Network authorization and credentials

The app SHALL request the macOS authorization needed to identify Wi-Fi networks at startup, retain an explicit Enable Wi-Fi discovery action in Settings, and refresh discovery after permission completion. Denial SHALL preserve history management and manual Current Wi-Fi connection without fabricated network identities or repeated prompts. A Bluetooth route requiring automatic association SHALL establish Wi-Fi access prerequisites before camera wake/WLAN writes and use valid same-attempt BLE credentials before any saved-password lookup. BLE-derived credentials SHALL remain native memory only. If rejected, the route MAY refresh once on its existing protected BLE link and otherwise SHALL report failure with explicit Wi-Fi-only recovery rather than silently using stale credentials. Wi-Fi-only routes SHALL retain read-only macOS user-domain then system-domain Keychain priority by exact SSID bytes, then app-owned credentials, then native secure entry with optional remembering initially off. Missing/inaccessible macOS items SHALL permit fallback; explicit macOS authorization cancellation SHALL stop the attempt. Rejected saved passwords SHALL advance without retrying identical values. Manually entered opted-in credentials SHALL be persisted only after successful camera verification; unremembered values SHALL remain in native memory. App-owned lookup/write errors SHALL be reported. No credentials SHALL enter WebKit, preferences or logs, and macOS credentials MUST NOT be copied to app-owned storage.

#### Scenario: Valid BLE credential
- **WHEN** automatic association needs a password and the protected BLE exchange supplies a valid one
- **THEN** the app joins using it without macOS Wi-Fi Keychain lookup, manual password entry or automatic credential persistence

#### Scenario: BLE password is rejected
- **WHEN** the camera-provided password fails association
- **THEN** the app refreshes it at most once on the same live protected connection or ends with recovery guidance, without an automatic saved-password fallback

#### Scenario: Wi-Fi discovery is denied
- **WHEN** a Bluetooth route cannot obtain the Wi-Fi access needed to join automatically
- **THEN** it reports the prerequisite failure before camera writes and preserves Current Wi-Fi operation

#### Scenario: Wi-Fi-only credential fallback
- **WHEN** an explicit Wi-Fi-only target needs protected association
- **THEN** the existing saved-credential/manual-entry policy applies, including cancellation and opt-in app storage

#### Scenario: Startup and late Wi-Fi authorization
- **WHEN** Wi-Fi-name authorization is undetermined at startup or later granted through the explicit discovery action
- **THEN** the app requests the needed authorization and refreshes discovery on completion without requiring Bluetooth access

### Requirement: Connection and download coordination

The app SHALL permit one connection attempt or cancellation cleanup at a time across BLE, Wi-Fi and HTTP. It SHALL associate callbacks with their originating attempt/link/session and reject obsolete results. Downloads MUST NOT start during setup or draining; setup, target switching and disconnect MUST NOT start during downloads. CANCEL SHALL prevent subsequent camera operations and discard attempt-owned secrets/results, but MUST NOT claim to reverse completed camera writes or Wi-Fi association. A synchronous association already in flight SHALL keep admission locked until it returns. No stale result SHALL publish photos, restore forgotten history, start later stages or affect a newer attempt.

#### Scenario: Repeated CONNECT activation
- **WHEN** CONNECT is activated during another attempt or cancellation drain
- **THEN** no additional BLE connection, GATT exchange, association or camera verification starts

#### Scenario: Cancel during blocking association
- **WHEN** CANCEL arrives after a CoreWLAN association call has begun
- **THEN** the app invalidates the attempt's effects, waits for that call to return before admitting another operation, and reports the actual resulting network without advancing to verification

#### Scenario: A timed-out GATT operation responds later
- **WHEN** an operation's connection has been retired and its delayed callback arrives
- **THEN** the result cannot satisfy a newer operation or change its UI/history

#### Scenario: Computer sleeps during setup
- **WHEN** the computer sleeps with an incomplete connection attempt
- **THEN** the app invalidates that setup and requires a new explicit CONNECT instead of resuming expired wake/WLAN writes
