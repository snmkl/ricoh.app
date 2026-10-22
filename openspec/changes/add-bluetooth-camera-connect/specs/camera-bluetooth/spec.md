## ADDED Requirements

### Requirement: Observe cameras without waking them

The app SHALL discover candidate Ricoh peripherals and remember verified camera identifiers independently of Wi-Fi networks. Discovery SHALL be bounded, foreground-only and paused during connection attempts/downloads. Discovery, retrieval of stored identifiers and system-connected-device inspection MUST NOT establish an app BLE connection, read protected characteristics, wake a camera or switch Wi-Fi. A name match alone MUST NOT authorize camera writes. A saved identifier MUST NOT be reported as a current bond or proof of presence.

#### Scenario: A remembered camera appears
- **WHEN** authorized foreground discovery observes a remembered camera
- **THEN** the app displays its name and fresh availability without connecting or waking it

#### Scenario: A saved camera is absent
- **WHEN** a camera has a stored peripheral identifier but no fresh presence observation
- **THEN** it remains a selectable remembered target without an Available or Connected assertion

#### Scenario: A camera is connected to macOS by another client
- **WHEN** system-connected-peripheral retrieval returns a relevant camera and this app has not connected
- **THEN** its state may say Connected on Mac but MUST NOT say Connected to this app or Camera ready

#### Scenario: A stale observation survives inactivity
- **WHEN** a prior availability observation has expired or the app resumes after inactivity
- **THEN** the app removes its fresh-presence assertion until discovery observes it again

### Requirement: Explicit Bluetooth access and protected setup

The app SHALL request Bluetooth access only after a Bluetooth-specific user action when permission is undetermined. Wi-Fi-only operation MUST remain usable when Bluetooth is off, unavailable or denied. CONNECT to a Bluetooth target SHALL establish this app's connection and supported identity before control writes, discover required characteristics by UUID and complete protected setup through macOS-managed pairing. Failure SHALL provide pairing guidance without guessing authentication state or repeatedly requesting permission.

#### Scenario: First Wi-Fi-only launch
- **WHEN** the user starts the app and uses Current Wi-Fi without choosing Bluetooth setup
- **THEN** the app does not trigger a Bluetooth authorization prompt

#### Scenario: Initial camera setup
- **WHEN** CONNECT reaches a supported camera that requires protected pairing
- **THEN** the app presents pairing instructions, allows the macOS pairing flow to complete within a bounded setup stage and retains cancellation

#### Scenario: Unsupported candidate
- **WHEN** a candidate lacks the supported camera identity or required GATT properties
- **THEN** the app reports unsupported Bluetooth control and performs no power or WLAN writes

### Requirement: Use the Mac Computer Name as the paired-device label

After protected identity and state checks succeed during an explicit Bluetooth CONNECT, the app SHALL obtain the current macOS Computer Name and write its UTF-8 bytes to the documented Paired Device Name characteristic with response. It SHALL refresh the name on each connection without adding a MAC address, app suffix or NUL terminator. Unavailable, blank or embedded-NUL names SHALL be skipped. Discovery and unsupported-device setup MUST NOT write the name. Missing support or a rejected label SHALL remain best effort while the BLE link is valid; pairing failure, timeout or loss of that link SHALL stop setup.

#### Scenario: Connect from a named Mac
- **WHEN** protected setup identifies a supported camera and the Mac has a valid Computer Name
- **THEN** the app sends that name, including Unicode characters, as the camera's paired-device label before power/WLAN activation

#### Scenario: Rename the Mac
- **WHEN** the Computer Name changes between Bluetooth connections
- **THEN** the next connection sends the current name rather than a cached label

#### Scenario: Camera cannot accept a label
- **WHEN** the name characteristic is absent or rejects the label while the BLE link remains valid
- **THEN** setup continues without retrying the label or blocking the Wi-Fi handoff

### Requirement: Prepare camera Wi-Fi using documented BLE commands

An explicit Bluetooth CONNECT SHALL read camera identity, firmware, power and operation state, request power on only for a documented off/sleep state, enable WLAN AP mode when required, and obtain valid SSID/passphrase values. Power and Network Type writes MUST use the documented UUIDs, one-byte values and write-with-response. Operations SHALL be serialized and bounded; a write acknowledgment alone MUST NOT establish AP success. The app MUST NOT force capture mode, implement speculative authentication or loop on authentication/application write rejection.

#### Scenario: Off or sleeping camera
- **WHEN** protected setup succeeds and Camera Power reports off or sleep
- **THEN** CONNECT requests power on, waits for readiness and proceeds to WLAN preparation

#### Scenario: Camera already prepared
- **WHEN** power and Network Type already report on and AP mode
- **THEN** the app avoids redundant writes and obtains credentials for the Wi-Fi handoff

#### Scenario: BLE startup mode
- **WHEN** power is on and the operation mode indicates BLE startup
- **THEN** the app may prepare WLAN without writing capture mode or claiming shooting readiness

#### Scenario: WLAN command is rejected
- **WHEN** the Network Type write fails with `0x80` or another application rejection
- **THEN** the app ends automatic activation with a stage-specific error and offers explicit manual Wi-Fi recovery without repeating the rejected command

#### Scenario: BLE drops during AP activation
- **WHEN** BLE disconnects after WLAN was requested
- **THEN** the app continues only if valid same-attempt credentials exist and the matching AP is observed
- **AND** otherwise it reports a BLE setup failure without claiming Wi-Fi success

### Requirement: Keep setup transport separate from library readiness

BLE connection SHALL mean an established app BLE link, independently of camera HTTP readiness. After successful handoff the app SHALL release its BLE setup link and show that release without clearing the verified Wi-Fi library session. BLE loss SHALL NOT by itself clear a working Wi-Fi session. Discovery and health checks MUST NOT reconnect BLE or wake a camera automatically. Disconnect/cancel MUST NOT issue camera power-off, WLAN-off or network-restoration commands.

#### Scenario: Handoff completes
- **WHEN** the Wi-Fi library is fully verified
- **THEN** the app releases BLE, retains the named camera and verified library, and displays the actual released/disconnected BLE state

#### Scenario: BLE loss with healthy Wi-Fi
- **WHEN** BLE is released or lost while Wi-Fi and camera health remain valid
- **THEN** the app updates Bluetooth status without clearing photos or disabling downloads

#### Scenario: Disconnect the app session
- **WHEN** the user disconnects outside an active download
- **THEN** the app releases its BLE resources and clears its library session without powering off the camera or changing Wi-Fi association

### Requirement: Remember devices and isolate secrets

The app SHALL persist supported camera identity only after a successful protected identification exchange, separately recording full library success and verified network links. Device history SHALL store no credentials or transient presence/link state. BLE-derived credentials SHALL remain native attempt-owned memory and be cleared on termination; they MUST NOT enter WebKit, preferences or logs. Forget camera SHALL remove only app camera history/default selection and MUST leave macOS pairing, network history and Wi-Fi credentials unchanged. Forget network SHALL remove that network's device-history link without removing its camera. Prior callbacks MUST NOT undo either Forget action.

#### Scenario: Bluetooth succeeds but Wi-Fi fails
- **WHEN** protected identification succeeds and WLAN activation fails
- **THEN** the camera may be remembered for retry but is not recorded as a successful library connection

#### Scenario: Forget a remembered camera
- **WHEN** the user forgets a camera not involved in an active attempt/session/download
- **THEN** its app device record and default selection disappear, while OS pairing and network history remain intact

#### Scenario: Forget the active camera
- **WHEN** a camera is involved in an active attempt/session/download
- **THEN** Forget camera is unavailable with an explanation until that activity ends

#### Scenario: Forget a linked network
- **WHEN** a remembered Wi-Fi network linked to a device is forgotten
- **THEN** the device remains remembered and its network link is removed without being restored by older callbacks

#### Scenario: Finish or cancel with credentials in memory
- **WHEN** a BLE connection attempt succeeds, fails or is cancelled
- **THEN** its credentials are cleared without persistence or disclosure through events or logs
