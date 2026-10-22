## ADDED Requirements

### Requirement: Remember verified camera networks

The app SHALL remember the current Wi-Fi network only after a successful camera ping and a successful, valid photo-list response. An empty valid photo list SHALL count as success. The SSID MUST be available and consistent throughout verification. Entries SHALL persist across launches, deduplicate by exact SSID identity, preserve their display name, and record the last successful camera-connection time. Failed attempts MUST NOT create or refresh entries.

#### Scenario: First successful connection
- **WHEN** the user connects on a network with an identifiable stable SSID and the camera verification succeeds
- **THEN** the app remembers that SSID and its successful connection time

#### Scenario: Successful connection to an empty camera
- **WHEN** camera ping succeeds and its photo-list response is valid but empty
- **THEN** the app treats the camera connection as successful and remembers the identifiable stable network

#### Scenario: Repeated successful connection
- **WHEN** another successful camera connection occurs on an already remembered SSID
- **THEN** the app updates that entry's timestamp without adding a duplicate

#### Scenario: Failed or ambiguous connection
- **WHEN** verification fails, the photo response is invalid, the SSID changes during verification, or the SSID cannot be determined
- **THEN** the app does not add or refresh a network entry

#### Scenario: Wi-Fi identity becomes available late
- **WHEN** a camera connection succeeds before its SSID is readable, and that identity later becomes available
- **THEN** the app performs fresh camera verification with a consistent SSID and remembers the network without requiring another CONNECT
- **AND** a Forget action taken since the original attempt prevents that attempt from restoring the entry

#### Scenario: Wi-Fi identity remains unavailable
- **WHEN** camera verification succeeds but the app cannot read a stable SSID
- **THEN** the connection status explains why the network was not remembered and gives Location Services guidance when authorization is missing

### Requirement: Remove known networks

Every known network SHALL have a Forget action in Settings. A successful Forget SHALL remove its persisted history entry, reconnect selection, and app-owned credential, and update both Settings and the reconnect dropdown. It MUST NOT remove macOS's saved Wi-Fi network or macOS-owned password, and MUST NOT disconnect the current network. Forget MUST survive restart and stale callbacks from an already running attempt; a later newly started successful camera connection SHALL be able to learn the network again. Credential-deletion failure MUST be reported and leave the entry available for retry.

#### Scenario: Forget an available network
- **WHEN** the user successfully forgets a remembered network that is currently discoverable
- **THEN** its Settings row and reconnect option disappear and its app-owned credential is deleted, while the selector retains its current-network option and name

#### Scenario: Forget the currently joined network
- **WHEN** the user successfully forgets the network currently used by the app
- **THEN** its app history and app-owned credential are removed while the existing Wi-Fi association and macOS saved network remain intact

#### Scenario: Restart after forgetting
- **WHEN** the app restarts after a network was forgotten
- **THEN** that network remains absent from app history until a new successful camera connection learns it

#### Scenario: Late attempt completes after forgetting
- **WHEN** a connection attempt that began before Forget finishes or an old scan result arrives afterward
- **THEN** it does not restore the forgotten history entry or reconnect option

#### Scenario: Learn a forgotten network again
- **WHEN** the user starts a new camera connection on the forgotten network and verification succeeds
- **THEN** the app adds a new history entry for that SSID

#### Scenario: Credential deletion fails
- **WHEN** Forget cannot remove an app-owned credential
- **THEN** the app reports the failure and retains the entry so the user can retry rather than reporting complete removal

### Requirement: Wi-Fi selector and current network

The main connection controls SHALL always show a Wi-Fi selector whose default option displays the current network's name with a current-network indication. When the current name cannot be read or Wi-Fi is disconnected, it SHALL show that state explicitly without inventing a name. Other options SHALL contain only currently available remembered camera networks, without duplicating the current SSID. All remembered networks SHALL remain manageable in Settings regardless of availability. Explicit camera selections SHALL persist while available; disappearance or Forget SHALL remove the target and select the current-network option rather than another camera. With discovery authorized, the active app SHALL periodically refresh remembered-network availability, including when no camera was nearby at launch, pausing scans during connection setup and downloads. Current-network identity SHALL update independently of scans, including without remembered networks and during downloads. Selecting an item or receiving a scan or identity result MUST NOT itself change Wi-Fi association or contact the camera.

#### Scenario: No known network is nearby
- **WHEN** history is empty or discovery finds no remembered SSID
- **THEN** the selector remains visible with its named current-network option or explicit unavailable/disconnected state, and CONNECT on Current Wi-Fi remains usable

#### Scenario: Nearby remembered networks are found
- **WHEN** discovery finds one or more remembered SSIDs
- **THEN** the selector contains the named current-network option plus those remembered SSIDs, excluding unavailable networks and duplicates of the current network

#### Scenario: Selected camera network goes away
- **WHEN** a selected remembered camera SSID is absent from the next discovery result
- **THEN** the app removes its selector option and falls back to the current-network option without joining another network or removing the remembered history

#### Scenario: Current network changes or is forgotten
- **WHEN** the current Wi-Fi changes or its app history is forgotten
- **THEN** the selector continues to show the latest readable current network name, including if it is unrelated to a camera or not remembered

#### Scenario: Current network updates during downloads
- **WHEN** a download prevents scanning and the current Wi-Fi identity changes
- **THEN** a lightweight interface read updates the current-network option without starting a scan or association

#### Scenario: Change the target without connecting
- **WHEN** the user chooses another network in the dropdown
- **THEN** only the target changes, with association deferred until CONNECT is activated

#### Scenario: Camera Wi-Fi appears after launch
- **WHEN** a remembered camera network becomes available while the app is active after an initial scan found no nearby camera
- **THEN** a subsequent automatic scan adds its dropdown option without requiring app restart, app reactivation, or manual refresh
- **AND** discovery alone does not join the network or contact the camera

#### Scenario: Discovery is temporarily paused
- **WHEN** the app is inactive, connecting, downloading, or lacks authorization for Wi-Fi names
- **THEN** automatic scans pause and resume when the app is active and eligible, without repeatedly requesting permission

### Requirement: Join selected Wi-Fi before camera connection

When CONNECT targets an available remembered network, the app SHALL revalidate its availability, join it if necessary, wait for local network readiness, and then perform camera verification. If already joined, it SHALL skip reassociation. Current Wi-Fi SHALL use the existing network without switching. The app MUST NOT require internet connectivity on camera Wi-Fi. Network readiness and camera verification SHALL have bounded waits and distinguish join failure from camera unavailability. Selecting a target MUST NOT authorize switching to another network when the requested one fails.

#### Scenario: Reconnect from another Wi-Fi network
- **WHEN** the user activates CONNECT with an available remembered camera network selected
- **THEN** the app joins that SSID, waits for local readiness, verifies the camera, and displays its photos only after verification succeeds

#### Scenario: Selected camera network is already joined
- **WHEN** CONNECT targets the already joined SSID
- **THEN** the app verifies the camera without disconnecting and reassociating

#### Scenario: Use current network explicitly
- **WHEN** CONNECT is activated with Current Wi-Fi selected
- **THEN** the app verifies the camera over the current network without switching Wi-Fi

#### Scenario: Selected network disappears or cannot be joined
- **WHEN** a selected target is no longer discoverable or association fails
- **THEN** the app reports the network-stage failure, performs no camera verification for that attempt, and does not silently select another network

#### Scenario: Camera is slow or unavailable after joining
- **WHEN** association succeeds but the camera is not immediately reachable
- **THEN** the app retries verification within a finite interval and reports camera unavailability if that interval expires

### Requirement: Network authorization and credentials

The app SHALL request the macOS authorization needed to identify Wi-Fi networks at startup, explaining its discovery purpose, and provide an explicit Enable Wi-Fi discovery action in Settings when permission is missing. Permission completion SHALL refresh discovery. Authorization denial or unavailable Wi-Fi discovery MUST NOT prevent manual Current Wi-Fi camera connection. For a selected protected network needing association, the app SHALL prioritize its existing macOS Wi-Fi Keychain password, searching the user then system domain by exact SSID bytes, then fall back to an app-owned saved password and native secure entry when necessary. Missing or inaccessible macOS credentials SHALL permit fallback; explicit authorization cancellation SHALL stop the attempt without another prompt. A rejected stored password SHALL advance to the next source without repeating identical rejected saved credentials. Manual entry SHALL offer Remember password initially off, persisting only in the app-owned Keychain after successful camera verification when requested. The macOS credential lookup MUST be read-only, and reused macOS passwords MUST NOT be copied into the app's store. Passwords MUST NOT appear in preferences, WebKit messages, or logs. App-owned credential-access failure or manual cancellation MUST end that join attempt with an actionable result.

#### Scenario: Startup requests discovery permission
- **WHEN** the app starts with authorization not yet determined
- **THEN** it requests macOS Location Services authorization and refreshes discovery after the response, while keeping the app usable

#### Scenario: Wi-Fi name authorization is denied
- **WHEN** the user denies authorization required for Wi-Fi discovery or network names
- **THEN** the app explains the unavailable reconnect functionality, preserves stored history for management, avoids fabricated network names, and permits manual Current Wi-Fi connection

#### Scenario: First reconnect needs a password
- **WHEN** a selected protected network has no usable macOS or app-owned saved credential
- **THEN** the app requests its password through native secure entry before association and offers optional Keychain storage

#### Scenario: Reuse the macOS saved Wi-Fi password
- **WHEN** CONNECT targets another protected network and macOS Keychain provides its saved password
- **THEN** the app uses it before any app-owned password, without requiring manual Wi-Fi password entry or copying it into app-owned storage
- **AND** macOS may request authorization for Keychain access

#### Scenario: Saved macOS credentials are unavailable or rejected
- **WHEN** the macOS credential is missing, inaccessible, or cannot join the selected network
- **THEN** the app tries its own saved credential and then manual entry if necessary, without retrying an identical rejected stored password

#### Scenario: Cancel macOS Keychain access
- **WHEN** the user explicitly cancels the macOS Keychain authorization request
- **THEN** the connection attempt ends as cancelled without Wi-Fi association or a subsequent app password prompt

#### Scenario: Credential lookup is unnecessary
- **WHEN** the app discovers networks, checks camera health, connects on the already joined network, or joins an open network
- **THEN** it does not request macOS Wi-Fi passwords

#### Scenario: Remember a verified password
- **WHEN** the user opts to remember a password and the resulting camera connection succeeds
- **THEN** the app stores the credential in its own Keychain namespace for later reconnects

#### Scenario: Do not remember or cancel credentials
- **WHEN** the user leaves Remember password off or cancels the credential prompt
- **THEN** no password is persisted, and cancellation starts no Wi-Fi association or camera verification

#### Scenario: Keychain access fails
- **WHEN** an app-owned credential cannot be accessed or a requested app-owned credential write fails
- **THEN** the app reports the credential error without leaking the password or falsely reporting that it was remembered

### Requirement: Connection and download coordination

The app SHALL permit one connection attempt at a time and associate asynchronous updates with that attempt. It MUST reject Wi-Fi switching while a download is active and reject downloads while a connection attempt is active. Stale scan or connection callbacks MUST NOT replace the active target, photo list, or status of a newer attempt.

#### Scenario: Repeated CONNECT activation
- **WHEN** CONNECT is activated again while an attempt is running
- **THEN** no overlapping scan, association, credential prompt, or camera-verification workflow starts

#### Scenario: Connection and download overlap
- **WHEN** the user requests reconnection during a download or requests a download during connection setup
- **THEN** the conflicting action is unavailable in the interface and rejected by the native handler

#### Scenario: Old attempt responds late
- **WHEN** a scan or camera callback from an obsolete attempt arrives
- **THEN** it does not change the current attempt's target, displayed photos, status, or network history

### Requirement: Detect loss of a connected camera

While connected, the app SHALL periodically check the local Wi-Fi interface and camera reachability without requiring internet access or readable SSIDs. Loss of Wi-Fi, a change to another identifiable SSID, or a failed camera health check SHALL end the session, clear its displayed photos, selection, and preview, disable photo actions, and show disconnected status. Known network history SHALL remain available in Settings. Health-check callbacks from an old session MUST NOT affect a newer connection.

#### Scenario: Wi-Fi disconnects or changes
- **WHEN** a connected session loses its local Wi-Fi connection or moves to another identifiable SSID
- **THEN** the app clears the camera view and connected indicator after detecting the change, while preserving remembered network history

#### Scenario: Camera disappears without SSID authorization
- **WHEN** Wi-Fi names are unavailable and the connected camera stops responding to health checks
- **THEN** the app clears the camera view and displays disconnected status

#### Scenario: Old health check completes after reconnecting
- **WHEN** a health check from a previous connection returns after a new attempt has started
- **THEN** it cannot clear the new connection's photos or replace its status
