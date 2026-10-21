## 1. Native preferences and platform boundaries

- [x] 1.1 Add a versioned native preferences store with isolated-test storage, folder bookmarks, ZIP/Separate files defaults, exact-SSID network history, and safe fallback for missing or invalid values.
- [x] 1.2 Add the contextual Location Services usage description and required CoreWLAN, CoreLocation, and Security framework linkage to both `build.sh` and `Makefile`, preserving the bundle identity and minimum macOS version.
- [x] 1.3 Introduce testable Wi-Fi, authorization, and app-owned credential adapters; validate current-SSID lookup, discovery, and Keychain behavior with the actual ad-hoc-signed bundle before relying on those APIs in the UI.

## 2. Settings interface and native pickers

- [x] 2.1 Add the Settings panel, settings button, and Command-comma menu action; expose the destination, batch format, and all known networks with Forget actions through a native-authoritative settings bridge.
- [x] 2.2 Connect folder selection to a native directory picker, bookmark persistence, and validation; provide accessible controls, focus restoration, Escape/Close behavior, and immediate display of saved preference changes.

## 3. Direct download output

- [x] 3.1 Resolve or request a usable directory before transferring, retain the native admission guard during the picker, snapshot format and destination for the operation, and handle cancellation without transferring or changing existing preferences.
- [x] 3.2 Replace per-download save dialogs with direct output: original single images, original files for Separate files batches, or one ZIP for ZIP batches, retaining sequential staging and archive validation.
- [x] 3.3 Implement exclusive destination-name reservation with suffixes for existing files, same-basename selections, ZIP name collisions, and concurrent external writers; never overwrite an existing destination.
- [x] 3.4 Adapt progress stages and cleanup for destination preparation and direct publishing; publish only after staging/packaging succeeds and report partial destination-write failures with accurate saved/total counts.

## 4. Remembered networks and reconnect workflow

- [x] 4.1 Add a native connection coordinator that verifies ping and a valid photo-list response, accepts a valid empty list, distinguishes network and camera errors, bounds readiness/verification retries, and returns the verified photo list to WebKit.
- [x] 4.2 Add protected-network credential handling through native secure entry and optional app-owned Keychain storage, with remembering initially off, persistence only after successful verification, and explicit cancellation/access/write errors.
- [x] 4.3 Revalidate and join the selected available SSID before camera requests; skip association when already joined, preserve Current Wi-Fi as the manual path, and keep scans/association off the main thread without depending on internet connectivity.
- [x] 4.4 Record stable identifiable SSIDs only after success, refresh nearby-known discovery and the Wi-Fi selector, preserve explicit targets, and coordinate native/UI connection and download guards with attempt identifiers and stale-callback rejection.
- [x] 4.5 Implement Forget for every stored entry, deleting only app-owned credentials before history removal, retaining the entry on deletion failure, clearing affected dropdown selections, suppressing in-flight relearning, and allowing a later new successful connection to add it again.

## 5. Verification and minimal documentation

- [x] 5.1 Test preference defaults, persistence/relaunch, invalid values, moved or missing folder bookmarks, required folder selection and cancellation, and preference changes during an active operation.
- [x] 5.2 Extend the HTTP fixture/output tests for single originals, separate-file batches, valid ZIP contents, destination collisions including concurrent creation, transfer failure before publishing, and partial destination-write failure with accurate cleanup and counts.
- [x] 5.3 Use fake Wi-Fi/authorization adapters and a controllable clock to test available-network filtering, selection without association, join-before-camera ordering, already-joined and Current Wi-Fi paths, disappearance, readiness timeout, authorization denial, empty lists, and stale attempts.
- [x] 5.4 Test credential cancellation and Keychain access/write/deletion failures without touching system Wi-Fi credentials; verify passwords never enter preferences, WebKit events, or logs, and Forget survives restart and old callbacks while allowing later relearning.
- [x] 5.5 Extend WebKit checks for Settings controls and keyboard/accessibility behavior, dropdown visibility, immediate removal of forgotten entries, minimum-window layout, connection/download locking, and updated progress/terminal states.
- [x] 5.6 Verify both build paths and the bundled usage description; smoke-test the actual app's folder picker, direct exports, and Settings flow, and exercise real-camera discovery/reconnect when hardware is available, recording any authorization, signing, or hardware validation limits.
- [x] 5.7 Keep README changes brief: describe Settings, direct folder saving, the batch format choice, and the optional remembered-network reconnect control without adding implementation detail.

## 6. Observed-issue regressions

- [x] 6.1 Remember readable SSIDs when either CoreWLAN representation is available, reverify late identities, recover after late authorization, explain blocked remembering, and preserve Forget semantics.
- [x] 6.2 Monitor connected sessions for Wi-Fi/camera loss, clear stale camera UI, and reject health responses from old sessions; cover native state and WebKit with regression tests.
- [x] 6.3 Remove the Edit menu while retaining Settings and Quit, and verify the executable and standalone bundle builds.
- [x] 6.4 Refresh discovery periodically for remembered networks appearing after launch, throttle scans, pause during downloads/connections or inactivity, request startup authorization, and cover delayed discovery and permission completion through regression tests.

## 7. Reuse macOS Wi-Fi credentials

- [x] 7.1 Add read-only saved Wi-Fi Keychain lookup by exact SSID bytes, user/system domain priority, cancellation handling, and fallback when unavailable, using an injected API boundary for tests.
- [x] 7.2 Prioritize macOS credentials before app-owned credentials and manual entry; fall back after a rejected saved password without duplicate retries, preserve opt-in app storage, and leave macOS credentials untouched by Forget.
- [x] 7.3 Cover credential priority, domain/status handling, skipped lookups, fallbacks, cancellation, password isolation, and Forget; run the full suite, both builds, and strict spec validation.

## 8. Always-visible current Wi-Fi selector

- [x] 8.1 Always display the current Wi-Fi name in the selector, with explicit unavailable/disconnected states and no duplicate option for the current SSID; retain an explicit available camera target and fall back to Current Wi-Fi when it disappears.
- [x] 8.2 Update current identity independently of scans, including with empty history and during downloads; preserve the current name when forgetting history or losing an old camera session, and remove unavailable GR reconnect choices.
- [x] 8.3 Verify native identity updates and the end-to-end disappearance/fallback path in WebKit; run regression tests, both build paths, and strict spec validation.

## 9. Native macOS Settings modal

- [x] 9.1 Move the settings form out of the browser's HTML dialog into a native titled/closable modal window, retaining its preferences, network controls, and system appearance.
- [x] 9.2 Support the standard close button, Command-W, Escape, Close control, repeated opening, browser focus restoration, and folder/credential sheets parented to Settings, while keeping asynchronous updates active.
- [x] 9.3 Verify native modal dismissal, reopening and live preference updates, nested-sheet protection, and download completion while Settings is open; run the full suite, both builds, and strict spec validation.
