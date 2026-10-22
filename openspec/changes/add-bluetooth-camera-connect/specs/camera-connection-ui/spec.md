## ADDED Requirements

### Requirement: One explicit connection target

The main window SHALL expose a connection-target selector for Bluetooth cameras, currently available remembered camera Wi-Fi networks and Current Wi-Fi. The Current Wi-Fi option SHALL display the network name or explicit unknown/disconnected state without repeating the name in a separate status row. The selector, Find cameras action immediately beside it, primary connection action and Settings SHALL fit on one header line at the minimum window width. The selector SHALL display a Bluetooth or Wi-Fi icon for its selected route, with an equivalent accessible label. Remembered Bluetooth cameras SHALL remain selectable without an active AP or fresh presence observation. The app SHALL preserve an explicit Bluetooth target across discovery and relaunch, and MUST NOT silently substitute another camera. Initial setup SHALL default to Current Wi-Fi until the user selects a Bluetooth target. Selecting or discovering a target MUST NOT connect, wake or associate.

#### Scenario: Camera Wi-Fi is off
- **WHEN** the user selects a remembered Bluetooth camera whose AP is absent
- **THEN** CONNECT targets that camera's BLE identity rather than requiring an existing network entry

#### Scenario: Multiple cameras are discovered
- **WHEN** discovery finds multiple candidate cameras
- **THEN** the app shows distinguishable choices and requires explicit selection rather than controlling the first result

#### Scenario: Bluetooth target disappears
- **WHEN** the selected Bluetooth camera is no longer freshly observed
- **THEN** the app preserves it as the selected remembered target and shows its uncertain availability

#### Scenario: Explicit Wi-Fi route
- **WHEN** the user selects Current Wi-Fi or a remembered Wi-Fi network
- **THEN** CONNECT follows that Wi-Fi route without initiating BLE control

#### Scenario: Compact header and mode changes
- **WHEN** the window is at its minimum width and the user chooses Bluetooth or Wi-Fi
- **THEN** the connection controls remain on one header line, Find cameras is next to the selector, and the selector icon and accessible mode label follow that route without another Wi-Fi-name row

### Requirement: Truthful named Bluetooth and Wi-Fi status

The UI SHALL display the selected or app-connected Ricoh's observed name and distinguish remembered, freshly available, system-connected, app-connecting, app-connected and released/disconnected states. It SHALL show Bluetooth state independently of Wi-Fi association and verified library readiness. The selector SHALL prefer the device name and state without an identifier suffix unless needed to distinguish identically named devices; Settings SHALL also show its verified model where available. Library-ready indicators and photo actions MUST require successful HTTP verification, not Bluetooth connection alone.

#### Scenario: Connected BLE device is present
- **WHEN** this app establishes a BLE connection to the selected camera
- **THEN** the UI shows that device's name with Connected while retaining the current Wi-Fi/HTTP preparation state

#### Scenario: Credentials are read but Wi-Fi has not joined
- **WHEN** BLE preparation succeeds before Wi-Fi verification
- **THEN** the UI continues to show preparation progress and does not enable photo actions

#### Scenario: Setup link is released
- **WHEN** BLE is deliberately released after handoff
- **THEN** the device name remains visible with Released or Disconnected and Wi-Fi library readiness remains independently visible

### Requirement: Connect action owns the complete handoff

CONNECT to a Bluetooth camera SHALL initiate discovery/retrieval, protected connection, camera preparation, AP activation, exact-network association and HTTP verification as one attempt. The primary action SHALL become CANCEL during preparation, CANCELLING while native work drains and DISCONNECT after success. Native handlers and UI SHALL prevent overlapping attempts and disable switching/disconnect during a download. Stage status SHALL identify what remains in progress, with an accessible live region and text labels usable at the minimum window size.

#### Scenario: One-click wake and connection
- **WHEN** a configured Bluetooth camera is selected and CONNECT is activated
- **THEN** the app runs the complete BLE-to-Wi-Fi flow without another routine connect action or Wi-Fi password entry when valid BLE credentials are available
- **AND** any required OS authorization or initial pairing interaction remains visible

#### Scenario: Cancellation requires draining
- **WHEN** CANCEL is activated while association or BLE cleanup is still in flight
- **THEN** the UI shows CANCELLING and keeps conflicting actions disabled until native work is drained

#### Scenario: Download in progress
- **WHEN** a download is active
- **THEN** connection-target changes, connection setup and disconnect are unavailable in both UI and native admission

### Requirement: Setup and manual recovery remain visible

Settings SHALL provide Bluetooth access/discovery controls, setup guidance and remembered-device management separately from Wi-Fi network history. Errors SHALL name the failed stage and offer relevant recovery. Bluetooth denial or remote activation rejection MUST leave the existing manual Wi-Fi route available. A suggested manual route SHALL require explicit user activation before association.

#### Scenario: First Bluetooth use
- **WHEN** the user opens Bluetooth setup
- **THEN** the app explains camera pairing and On anytime, offers explicit discovery/access controls and does not wake the camera merely by opening Settings

#### Scenario: Automatic Wi-Fi activation is rejected
- **WHEN** the camera rejects the documented WLAN command
- **THEN** the UI explains remote activation failed and offers instructions plus an explicit Wi-Fi-only route

#### Scenario: Bluetooth permission is denied
- **WHEN** macOS denies Bluetooth access
- **THEN** the UI explains where to enable it, avoids repeated prompts and leaves Current Wi-Fi selectable
