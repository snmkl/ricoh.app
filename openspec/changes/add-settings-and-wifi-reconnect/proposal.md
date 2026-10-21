## Why

Repeated imports currently require a save dialog, force multi-photo downloads into ZIPs, and require switching to the camera's Wi-Fi outside the app. Persistent settings and remembered camera networks would make importing photos a shorter, repeatable workflow.

## What Changes

- Add a native macOS Settings modal window, accessible from a settings button and Command-comma, with a standard title-bar close button, Command-W/Escape dismissal, chosen download folder, default batch export format, and known camera networks.
- Save downloads directly into the chosen folder. Choose or repair the destination before transferring when no usable folder is configured; avoid per-download save dialogs and silent overwrites.
- Offer Separate files and ZIP archive for multi-photo downloads. Keep single-photo downloads as original image files and retain ZIP as the initial batch default.
- Remember the current Wi-Fi name only after a successful camera connection, updating existing entries rather than duplicating them.
- Always show a Wi-Fi selector with the current network's name and only currently available remembered camera networks. Default to the current connection, preserve explicit available targets, and remove unavailable camera choices. Join a selected camera network before contacting the camera.
- Provide Forget on every remembered network. Remove it from the app's history and reconnect choices, without removing macOS's saved Wi-Fi network; a later successful camera connection can add it again.
- Handle Wi-Fi authorization, password entry, network readiness, and camera failures as distinct states. Prioritize an existing macOS Wi-Fi Keychain password, then an app-owned saved password, then manual entry. Permit optional app-owned Keychain password storage and remove only those app-owned credentials when forgetting the network.
- Preserve existing download progress, staging, and failure handling while adapting destination and export stages to the new preferences.

## Capabilities

### New Capabilities

- `app-settings`: Settings presentation and persistence, folder selection, direct saving, export format selection, filename collision handling, and per-download preference snapshots.
- `camera-networks`: Successful-connection history, removable entries, nearby known-network choices, Wi-Fi association before camera connection, credentials, and permission fallback.

### Modified Capabilities

- `download-progress`: Replace the normal save-dialog stage with destination preparation before transfer and direct saving afterward; support separate-file batches and report partial destination-write failures accurately.

## Impact

- `GRBrowser.swift`: Embedded settings UI, connection controls and state, native settings/message bridge, persistence, folder picker, Wi-Fi service, and download finalization.
- `Info.plist`, `build.sh`, and `Makefile`: Location usage description and required Apple framework linkage for both supported build paths.
- `tests/`: Settings and network service fakes, lifecycle tests, direct-save/output tests, and WebKit UI coverage.
- Apple Foundation/UserDefaults, AppKit folder and credential prompts, CoreWLAN, CoreLocation, and Security/Keychain; no third-party dependencies.
- macOS 13.3 minimum, existing camera API endpoints, and the current app bundle identity remain supported. Previously configured settings do not exist, so the first folder is selected by the user.
