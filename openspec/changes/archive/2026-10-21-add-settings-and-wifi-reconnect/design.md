## Context

The application is a small AppKit executable with a WebKit interface embedded in `GRBrowser.swift`. `doConnect()` performs camera requests from JavaScript through the custom scheme handler. `DownloadHandler` already stages sequential transfers, creates a ZIP for multiple photos, and presents `NSSavePanel` after transferring. There is no settings store, network history, Wi-Fi association service, or app settings menu.

The proposal introduces preferences that cross the JavaScript/native boundary and changes destination selection, output packaging, and connection sequencing. Existing progress events, operation identifiers, native admission guards, and staging cleanup should be retained.

## Goals / Non-Goals

**Goals:**

- Persist a user-chosen folder and batch export preference, then save directly without repetitive dialogs.
- Remember verified camera Wi-Fi networks, show nearby remembered choices, and join the selected network before contacting the camera.
- Make every remembered network removable and keep its removal distinct from macOS Wi-Fi configuration.
- Preserve responsive browsing, truthful progress, explicit failures, and macOS 13.3 compatibility.

**Non-Goals:**

- Automatic network switching at startup, automatic switching back after importing, or background reconnect loops.
- Managing all macOS remembered networks, removing system credentials, or supporting enterprise Wi-Fi configuration.
- Changing camera endpoints, image encoding, thumbnail behavior, or the download transport's sequential execution.
- Implementing features in the proposal phase.

## Decisions

### 1. Host Settings in a native macOS modal and own data natively

Use a titled, closable AppKit `NSPanel` for Settings, opened by the settings button or standard Command-comma menu action. AppKit owns its title bar, red close button, keyboard-window focus, and modal event loop. Command-W, Escape, and the form's Close button dismiss only Settings and return focus to the browser. Reuse the same window on later opens and do not add another modal when one is already open. Retain only the app menu with Settings and Quit; do not add an Edit menu.

Keep the small settings form in a separate `WKWebView` inside the native panel, using system fonts and light/dark appearance. It exposes folder and Separate files / ZIP archive choices under Downloads and known camera networks with per-row Forget below. The browser no longer contains an HTML dialog. Swift remains authoritative through the same settings bridge, broadcasting current values to both views; do not keep another persisted copy in WebKit local storage. A weak script-message proxy avoids a retain cycle through the retained settings window.

Schedule modal presentation on the main run loop after a WebKit/main-queue callback returns. This permits asynchronous network, preference, and download callbacks to continue during AppKit's modal loop. Native directory pickers attach to the Settings window that sent their request, and the Settings parent cannot close while a child sheet is attached. Secure credential prompts use the visible modal as their parent too. Closing Settings must not close the browser, terminate the app, cancel downloads, or reset persisted preferences.

Persist a versioned preferences record with a folder bookmark, batch format, and network entries containing exact SSID identity and last successful camera-connection time. Use `UserDefaults` for preferences and Keychain for optional passwords. The first folder is unset, the initial batch format is ZIP, and network history is empty. Invalid stored values fall back to these defaults. Resolve and refresh folder bookmarks; security-scoped access is relevant if App Sandbox is adopted, rather than a requirement imposed on the current unsandboxed build.

### 2. Resolve the destination before transferring and snapshot preferences

When a download is accepted, capture its selected files and format. Resolve the configured destination and check that it is an available writable directory. If absent or unavailable, show one native directory picker before starting camera transfers. Store a successfully selected replacement and freeze that folder for the operation. Picker dismissal ends the operation without a transfer or preference change.

Changes made in Settings affect subsequent downloads, not active operations. Preserve one-download admission through folder selection, staging, optional ZIP creation, and destination writes. A separate connection guard prevents Wi-Fi switching during an active download; downloads cannot begin during an active connection attempt.

### 3. Keep staged transfers and make output depend on format

Both export modes download sequentially into operation-owned staging. A single photo remains its original image file regardless of the batch preference. Multi-photo ZIP mode uses the existing archive step; Separate files skips archiving and publishes the original files directly in the chosen folder.

Preserve each original basename where possible. Resolve collisions, including duplicate basenames within a batch, with numeric suffixes before the extension. Reserve destination names exclusively so an external write between checking and publishing cannot cause an overwrite. Apply the same rule to dated ZIP names.

Complete all transfers and optional packaging before publishing output. This preserves the existing behavior that a failed transfer leaves the destination untouched. Publishing multiple individual files cannot be guaranteed atomic across the whole batch: if a later destination write fails, retain already saved files and report the saved/total count as a failure. Never report a partial export as success, overwrite unrelated files, or remove pre-existing files during cleanup.

### 4. Use one native connection coordinator for joining and verification

Move the connection workflow behind a native coordinator so association, interface identity, HTTP success, and history updates share one lifecycle. Keep the scheme handler for photo previews and thumbnails. The connection bridge returns the verified photo list for JavaScript to render; a successful ping followed by a successful, valid photo-list response constitutes success, including an empty list.

Always show the main Wi-Fi selector. Its default option names the current network with a `(current)` label; explicitly show no Wi-Fi connection or an unavailable name when necessary. Include other remembered networks only while they are discoverable, excluding a duplicate entry for the current SSID. Preserve an explicit camera selection while it is available. If it disappears or is forgotten, remove its reconnect option and fall back to the current connection without selecting a different camera automatically. Selecting or scanning never joins a network; CONNECT is the user action that starts the attempt.

Scan off the main thread when needed, such as opening the dropdown or returning to the app, and revalidate the selected network on CONNECT. While the app is active and has remembered networks, use the existing timer to request a scan approximately every ten seconds. The interval is tracked by the coordinator's injected clock, and scans remain single-flight and pause while connecting or downloading. Do not scan periodically without authorization or remembered targets; polling must never request permission or join Wi-Fi. Give each attempt an identifier so stale scan and HTTP callbacks cannot update a later attempt.

Independently sample current-interface identity/readiness every two seconds while active, including with empty network history and during downloads. This inexpensive read does not scan or switch Wi-Fi. Send the current display name and readiness through the settings bridge. Keep the latest current name when an old camera session disconnects, and retain the current-network option even when that SSID is forgotten from app history. Generation checks discard identity reads queued before a new attempt or disconnect.

```text
CONNECT
  ├─ Current Wi-Fi or selected SSID already joined ─┐
  └─ Revalidate nearby SSID → obtain password → join│
                                                 ▼
                             wait for local network readiness
                                                 ▼
                               camera ping → valid photo list
                                                 ▼
                                 render photos → update history
```

Association and scanning use CoreWLAN through `CWWiFiClient`; authorization uses CoreLocation. Keep blocking association off the main thread. After association, wait for local address readiness and retry camera verification within a bounded interval rather than assuming the camera is immediately reachable. Camera Wi-Fi need not provide internet access. Distinguish network disappearance, join failure, camera timeout, and photo-list failure.

Only learn a network when its exact SSID is available and consistent across successful camera verification. Deduplicate by exact SSID identity, preserving display spelling; the same name is not proof of camera reachability. Do not infer a network name from the camera address or learn a failed attempt.

Accept either readable CoreWLAN SSID representation, retaining raw bytes when available. If identity arrives during verification, verify again with that identity. If permission or identity arrives after connecting, a full camera verification around stable identity can learn it later, subject to the original attempt's Forget revisions. Otherwise explain the missing history entry in the main status as well as Settings.

Keep a connected session after the attempt finishes. A two-second main-run-loop timer checks local Wi-Fi readiness and, while reachable, uses a separate HTTP verifier for a lightweight camera ping. Recheck on app activation too. Health checks do not require network scans, internet routes, or additional Wi-Fi-event entitlements. SSID changes, Wi-Fi loss, or ping failure invalidate the session and emit a session-tagged disconnected event to clear photos, selection, preview, and the connected indicator. Preserve known history. Ignore old health responses after another CONNECT starts; a download retains its own progress and failure reporting.

### 5. Make credentials and permissions explicit

Automatic Wi-Fi-name detection requires macOS Location Services authorization. Request it at startup for discovery, with an explanatory usage description, and refresh after the response. Settings shows Enable Wi-Fi discovery when permission is missing and Refresh Wi-Fi discovery when granted; the explicit action can request permission too. If authorization or discovery is unavailable, keep history visible in Settings, hide unavailable reconnect choices, explain the System Settings path when permission is blocked, and leave Current Wi-Fi camera connection usable. Do not invent a history entry for an unknown SSID or repeatedly prompt after denial. Inject the coordinator into bridge tests so the startup request is verified with fake authorization rather than prompting for real OS access.

CoreWLAN's protected-network association requires a password; a remembered SSID does not guarantee access to macOS's saved password. On explicit CONNECT to another protected network, first use `CWKeychainFindWiFiPassword` for that exact SSID's bytes in the user domain (including iCloud Keychain when enabled), then the system domain if no item was found. The lookup runs on the serial worker and may show a macOS authorization prompt. This adapter is read-only; it exposes no save/delete operations, and a reused macOS password is not copied into the app's store. Already-joined and open networks, discovery, and health checks never request these credentials.

If the macOS item is absent or inaccessible, fall back to the app-owned Keychain item, then native secure entry with an optional Remember password choice, initially off. A rejected stored credential advances to the next source; do not retry the same rejected password from both stores. Explicit cancellation of macOS Keychain authorization ends the attempt without another credential prompt or association. App-owned credential read failures remain errors. Keep unremembered passwords in memory only; persist a manually entered, opted-in credential after successful camera verification. Clear attempt-owned credential state on completion. Never send passwords into the WebKit bridge, preferences, or logs. These constraints follow Apple's [saved Wi-Fi Keychain lookup documentation](https://developer.apple.com/documentation/corewlan/cwkeychainfindwifipassword(_:_:_:)), [CoreWLAN association documentation](https://developer.apple.com/documentation/corewlan/cwinterface/associate%28to%3Apassword%3A%29), and [SSID authorization guidance](https://developer.apple.com/forums/thread/732431?answerId=758114022).

Validate SSID discovery, association, authorization prompts, and app-owned Keychain access with the actual ad-hoc-signed bundle early. The design does not assume silent system-Keychain access, a Developer ID requirement, or use of private Wi-Fi command-line tools. Cover macOS credential lookup status/domain behavior with an injected API boundary in automated tests; do not retrieve real Wi-Fi secrets or trigger their authorization dialogs in the test suite.

### 6. Forget removes app state and cannot trigger reconnection

Forget removes the history row, any selected reconnect target for that network, and the app-owned Keychain credential. It does not disassociate a working connection, forget the macOS Wi-Fi configuration, or delete a macOS-owned password. Update both Settings and the main selector immediately. Retain its current-network option and name even when no remembered nearby entries remain, including when the forgotten network is still the current Wi-Fi.

Delete any app-owned credential before committing history removal; a deletion failure retains the row with an error so the action can be retried. Suppress history writes from an attempt already running when its network is forgotten, using an attempt/revision check. A new explicit successful camera connection can learn the network again. This prevents a late completion or cached scan from undoing the user's Forget action.

## Risks / Trade-offs

- Wi-Fi names are unavailable without authorization, and signing affects real-device behavior → test the actual bundle early, explain unavailable discovery, and retain the current-network path.
- A discovered network may vanish or change before joining → revalidate on CONNECT, bound attempts, and avoid silently selecting a different target.
- Joining camera Wi-Fi may interrupt internet access → switch only after CONNECT names the selected target; do not automatically switch on launch or scan results.
- Network readiness can lag association → wait for local readiness and perform bounded camera retries without requiring internet reachability.
- The chosen folder can move, be disconnected, or lose write access → use bookmarks, validate before transfer, and report destination failures accurately.
- Individual-file publishing can fail midway → stage the full transfer first, preserve completed outputs, and report partial-save counts as failure.
- Forget and asynchronous completion can race → invalidate stale history updates and keep credential deletion scoped to app-owned items.

## Migration Plan

There are no existing preferences to migrate. Introduce a versioned preferences record with ZIP as the initial batch mode and no chosen folder or history. Continue allowing manual Current Wi-Fi connection before any network is remembered. Add the necessary framework linkage to both `build.sh` and `make run`, and retain the app bundle identity so preferences survive rebuilds.

Validate using isolated preferences, fake network and credential adapters, the local camera HTTP fixture, temporary export folders, and WebKit UI checks. Then exercise discovery and reconnecting with a real camera on the actual macOS bundle, recording any hardware or permission limits. Rollback reverts the settings/connection/export implementation; existing exported files remain ordinary images or ZIPs.

## Open Questions

No blocking product decisions remain. The concrete macOS authorization and association behavior of the ad-hoc-signed build needs early validation; failures must be surfaced rather than silently reducing the reconnect feature to an HTTP-only attempt.
