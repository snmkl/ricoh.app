## Context

`CameraConnection` already coordinates Wi-Fi identity, credentials, association, ping/photo verification and session health in `GRBrowser.swift`. It uses attempt identities and serial worker operations. `AppController` forwards settings snapshots and connection events to WebKit; `doConnect()` currently supplies only an SSID identity or Current Wi-Fi. There is no BLE service or cancellation/disconnect action. The existing verifier checks ping and photo list, but does not verify the BLE model against `/v1/props`.

The [investigation](../../../research/BLUETOOTH_WIFI_WAKE.md) documents reported WLAN activation on GR IIIx 1.41 and GR III 2.00, and rejection on GR III 1.92/2.10. Those are external reports, not tests of this app. An encrypted link alone may not be authenticated; macOS pairing behavior must be exercised on the intended camera. The completed settings/network baseline was archived before implementation; canonical network requirements now exist alongside this change's deltas.

## Goals / Non-Goals

**Goals:** CONNECT reaches a selected Ricoh over BLE, enables its AP and opens its library; the user sees which device is involved and what each transport is doing. Preserve deliberate Wi-Fi-only use, download exclusion, settings and truthful errors.

**Non-goals:** waking at launch or merely on discovery, unattended background reconnect, remote shutter, forced capture mode, automatic camera power-off, automatic restoration of home Wi-Fi, macOS bond management, firmware changes, or promising compatibility before hardware evidence.

## Decisions

### 1. One compact connection header

Use one non-wrapping header containing the app identity, connection-target selector, **Find cameras…**, primary connection action and Settings. Find cameras sits immediately after the selector. The selector has a Bluetooth or Wi-Fi SVG icon that follows the selected connection route; its accessible label and tooltip name that route too. It groups Bluetooth cameras, camera Wi-Fi networks and Current Wi-Fi. Keep the native select for keyboard and macOS popup behavior.

```text
GR IIIx  [ BT  GR_F323D3 · Available ▾ ] [Find cameras…] [CONNECT] ⚙
GR IIIx  [ BT  GR_F323D3 · Connected ▾ ] [Find cameras…] [CANCEL]  ⚙
GR IIIx  [ BT  GR_F323D3 · Released  ▾ ] [Find cameras…] [DISCONNECT] ⚙
GR IIIx  [ Wi-Fi  GR_F323D3 (current) ▾ ] [Find cameras…] [CONNECT] ⚙
```

BT and Wi-Fi above represent graphical icons in the implementation. Icons identify the selected setup route, not a claim that a BLE link remains active after handoff. Bluetooth options display the device's advertised/remembered name and truthful state, without repeating a UUID suffix. A verified model remains available in Settings. Released means the app has relinquished its BLE setup link; green camera-ready status still requires HTTP verification. System-connected, app-connected, available and remembered states remain distinct.

Show each Wi-Fi name only in the selector's corresponding option. Remove the separate Bluetooth/current-Wi-Fi status row, and put recovery actions beside the existing library status when needed. Current Wi-Fi remains accessible in the popup even while a Bluetooth target is selected, with explicit disconnected/name-unavailable wording. Its identity continues to refresh natively.

On first use default to Current Wi-Fi. Restore an explicit remembered Bluetooth target across launch/absence, preserve explicit available Wi-Fi choices, and never silently choose another camera. Disappearing Wi-Fi routes fall back to Current Wi-Fi. Selecting an option does not connect or wake the camera.

The header stays on one line at the 480-pixel minimum width. Let the selector shrink and truncate, preserving its full value in the tooltip/accessibility text; keep Find cameras, the primary action and Settings visible. CONNECT/CANCEL/DISCONNECT and the drain lock retain their existing lifecycle. Progress remains in the existing polite live region below the header; discovery and switching stay disabled during connection/download activity.

### 2. Discovery observes; connection is an explicit action

Construct the CoreBluetooth manager lazily after **Enable Bluetooth**, **Find cameras**, or CONNECT to a Bluetooth target when access has not been requested. Wi-Fi-only startup must not trigger a Bluetooth permission prompt. With previously granted access, initialize on activation and query Bluetooth state and system-connected peripherals without connecting to them.

Use a bounded scan on Find cameras / picker opening, then bounded foreground refreshes for remembered/selected devices, at most once per 30 seconds. Initial scan budget: 10 seconds; expire an Available observation after 45 seconds unless refreshed. Pause scans when inactive, connecting or downloading; expire stale observations after resume rather than presenting cached RSSI as presence. These are tunable starting values, not measured camera guarantees.

Retrieve the remembered peripheral identifier first for explicit reconnect, then query relevant system-connected peripherals, then scan if needed. A retrievable UUID is not availability evidence. Start with service filters validated against the camera advertisement; allow a bounded local-name candidate scan if the tested advertisement does not expose those services. Before any power/WLAN write, require expected services, characteristic properties and a supported GR III/IIIx identity read. Other Bluetooth devices never become control targets merely because their names match.

CoreBluetooth does not provide a reliable public query for the camera's bond authentication state. Delegate pairing UI to macOS via the protected GATT operation; provide camera-menu/passkey instructions alongside it. Do not add an app passkey field or assume CoreBluetooth exposes BlueZ/NimBLE pairing APIs. A failed protected operation produces re-pair guidance and ends the attempt; do not repeatedly force prompts or remove system bonds.

### 3. Extend the current coordinator, with an isolated BLE adapter

```text
WebKit controls ── target ID / action ──> AppController
                                              │
                                      CameraConnection
                                       /      |       \
                          BluetoothCamera  WiFiAccess  CameraVerification
                                  │          │              │
                         CoreBluetooth    CoreWLAN       URLSession

CameraConnection ── safe state snapshot + tagged events ──> both WebKit views
```

Keep `CameraConnection` as the only admission/attempt/session owner. Add a small typed Bluetooth transport boundary, pure protocol encoding/decoding, and a camera-discovery/history model; keep concrete delegates in separate files. Expose semantic operations such as connect, discover/read identity, prepare WLAN, and disconnect through that boundary. Inject transport, clock, scheduler and authorization for tests. Delegate state and coordinator changes use the main queue; retain peripherals strongly and perform blocking CoreWLAN/Keychain work on the serial worker.

Use independent discovery generation, attempt ID, BLE connection generation and HTTP session ID. Queue GATT operations one at a time, matching expected characteristic/callback and connection generation. Because CoreBluetooth callbacks carry no application request ID, a timed-out operation retires its connection; drain/cancel it before issuing another same-characteristic operation on that peripheral. Do not relabel late callbacks from an old link as the new generation. Service invalidation clears cached characteristics and forces rediscovery during a new explicit attempt.

### 4. An explicit, bounded handoff

```text
Idle → Prerequisites → Find exact target → BLE connect → Protected setup
                                                        │
                              Read identity/power/mode/credentials
                                                        │
                                 Wake if power says off or asleep
                                                        │
                                 Request WLAN AP; confirm readiness
                                                        │
                                Read/refresh SSID and passphrase
                                                        │
                    Join exact SSID → Local readiness → HTTP verify
                                                        │
                                   Release BLE → Library ready

Any stage → cancel/failure → drain native work → idle with useful error
Wi-Fi-only targets ──────────────────> existing join/HTTP path
```

Before camera writes, establish Bluetooth access/power and the Wi-Fi authorization/adapter prerequisites needed for this target. Location denial leaves Current Wi-Fi usable; do not wake the camera then discover that automatic joining is unavailable. Permission prompts occur before the AP activation interval. If already on a verified session for the selected camera, reuse that session rather than waking/rejoining it.

Read model, firmware, serial if available, power and operation mode. Capture valid same-attempt credentials before AP activation when readable, then refresh them afterward while BLE remains available. Credentials can be stale before AP activation; only a fresh post-activation read or successful association/HTTP verification establishes usability. Do not require capture mode for a download-only session or write Operation Mode speculatively. Power `1` in BLE startup is enough to attempt WLAN; if power reads `0` or `2`, request `01` and wait for readable readiness. Unknown states or failed reads fail with a specific result rather than guessing.

Discover by the UUIDs in the investigation. The Bluetooth Control service and its Paired Device Name characteristic are optional: their absence must not make otherwise supported camera control unusable. After protected identity/state checks, obtain the current Computer Name with `SCDynamicStoreCopyComputerName` and send its UTF-8 bytes to Paired Device Name (`FE3A32F8-A189-42DE-A391-BC81AE4DAA76`), with response, before conditional power/WLAN activation. Preserve Unicode and the exact name without a MAC address, suffix or NUL terminator; skip unavailable, blank or embedded-NUL names. Read the name again on each connection rather than persisting it. Reject payloads exceeding the peripheral's maximum write length. Unsupported/rejected metadata is best effort on a live link; pairing failure, timeout or disconnect ends setup. Cancellation/generation checks also guard this write and its continuation. Discovery never sets the label.

Write Camera Power and Network Type as exactly one byte, **with response**. The transport permits only these two `01` control writes and the validated UTF-8 name write. Skip power/WLAN writes when the read already shows the desired value. Confirm WLAN through readback and AP discovery; successful ATT completion alone is insufficient. Parse UTF-8 credentials strictly, remove trailing NUL padding without trimming meaningful spaces, validate SSID byte length and usable WPA credential format, and reject invalid values without echoing them.

If BLE drops immediately after requesting WLAN, continue only with valid credentials captured from that same authenticated attempt and an observed matching AP. Label Bluetooth disconnected, and complete the normal Wi-Fi/HTTP checks; otherwise fail at the BLE stage. Do not interpret a lost BLE link as evidence of AP success.

Use the BLE-supplied password first for this route, avoiding unnecessary macOS Keychain prompts. If rejected, refresh once on the same live BLE link; if no link or retry fails, stop with Wi-Fi/manual recovery guidance. Do not silently fall through to stale saved credentials for a different route. If already on the target SSID, skip association and password lookups.

Extend camera verification for the Bluetooth route to require `/v1/ping`, `/v1/props` identifying the expected supported model, and a valid `/v1/photos` response (empty allowed), while checking a stable exact SSID. Compare serial if both interfaces actually expose comparable serial values; model/SSID validation is not a cryptographic identity guarantee. Wi-Fi-only verification retains its existing contract.

Initial tunable budgets: scan 10 seconds, connect 15 seconds, discovery/ordinary GATT operation 5 seconds each, first protected setup/pairing 120 seconds with CANCEL available, WLAN readiness 10 seconds, and post-activation association plus HTTP verification 45 seconds total. Bound non-pairing pre-activation work to 45 seconds overall. A transient BLE connection failure may retry once within its stage budget; authentication, unsupported protocol and `0x80` errors do not loop. After computer sleep, invalidate setup and require a fresh explicit CONNECT rather than running expired writes on wake.

### 5. BLE is a setup transport; Wi-Fi owns the library session

Default: keep BLE through AP readiness, association and HTTP verification, then release this app's BLE connection. Preserve device identity and show Released. A release callback cannot invalidate the verified Wi-Fi session; existing Wi-Fi health checks remain authoritative. Discovery and HTTP health never automatically reconnect BLE or wake the camera.

This release policy is a product/implementation choice, not a claim that concurrent BLE/Wi-Fi is impossible. Validate it on hardware before enabling the automatic path. If the camera requires retaining BLE to keep its AP alive, change this documented lifecycle and its specs based on that evidence rather than silently shipping a different policy.

DISCONNECT clears the browser session and stops health checks/releases any app-owned BLE link. It does not turn off the camera, disable its AP, remove system pairing or switch the Mac back to home Wi-Fi. CANCEL similarly stops further work; it cannot undo a power/AP write or an association already issued. Explain any resulting network change in terminal status. Do not add cleanup writes whose safety or prior camera state is uncertain.

CoreWLAN association is synchronous on the worker and not reliably cancellable. After CANCEL, invalidate updates immediately but hold the native busy guard until the in-flight association returns; show Cancelling meanwhile. Only then admit a new attempt/download. A successful late association must not restore photos/history or start HTTP verification, but current-network observation should accurately show the resulting SSID. Stage deadlines stop subsequent work; they cannot guarantee that an already-issued OS call returns within our budget. If it overruns, show Waiting for macOS Wi-Fi operation rather than a false completed cancellation. Bluetooth cancellation similarly drains the connection before reuse.

### 6. Device history, credentials and Forget

Add a separate versioned preference record with remembered peripheral UUID, last verified model/display name, firmware, optional serial, last identified time, last successful library time and optional verified SSID link. Keep existing `settings.v1` unchanged. Do not persist RSSI, Available, Connected, power state or an unverified bond assertion.

Remember identity after a protected exchange identifies a supported camera, even when WLAN fails; record library success/link SSID only after full verification. This makes a pairing-success/WLAN-failure result recoverable. Restore the last explicitly selected remembered device, never an arbitrary first scan result. Multiple devices remain selectable. If its identifier becomes stale after OS changes, require explicit re-selection; do not remap silently by name.

Keep BLE-derived passwords in native attempt memory and clear at completion/cancel/failure. No automatic persistent copy in this change; Wi-Fi-only opt-in credential storage remains available through its existing route. Neither camera names nor passphrases are interpolated as HTML; use safe DOM text. Logs contain stage/result/model/firmware and redacted identifiers, never passkeys, passwords or raw credential GATT payloads.

Settings separates **Bluetooth cameras** from **Camera Wi-Fi networks**. Forget camera removes app identity/default selection and releases only app-owned BLE if applicable; disable it for a device in an active attempt/session/download and explain why. It leaves network history, app Wi-Fi credentials and macOS bonds untouched. Conversely Forget network removes its SSID link from remembered devices, not the camera itself. Revision checks prevent prior attempts from recreating either forgotten record; a new explicit successful operation can learn it again.

### 7. Fallbacks and failures are part of the connection design

| Failure | UI / recovery |
|---|---|
| Bluetooth off or denied | Name the adapter/permission issue; retain Current Wi-Fi; provide System Settings guidance. |
| Camera not found / connected to phone | Explain range, camera Bluetooth On anytime, and releasing the phone connection; retain exact selected target. |
| Protected read/pairing fails | Prompt camera-menu pairing and macOS passkey instructions; never assert the saved UUID proves pairing. |
| Unsupported model/characteristics | No power/WLAN writes; retain Wi-Fi-only route. |
| WLAN rejected, including `0x80` | Stop; state camera rejected remote Wi-Fi activation. Offer body Wi-Fi instructions and an explicit **Use camera Wi-Fi** action. |
| AP missing / invalid credentials / join fails | Name the failing stage; keep target and retry available; do not fall back to another network silently. |
| HTTP invalid/unavailable/wrong model | No library-ready indicator or new network association history; explain verification failure. |
| BLE lost after handoff | Update BLE status only; keep library if Wi-Fi health succeeds. |

Use camera Wi-Fi changes the route explicitly and requires CONNECT (or an explicitly labeled **Connect via Wi-Fi** action) before any association. If a BLE attempt obtained an exact SSID, it can suggest that network; otherwise show Current Wi-Fi/manual instructions. No speculative THETA authentication, raw GATT probing, firmware downgrade or camera-setting change is part of the shipped fallback.

## Migration and delivery

Archive the completed settings/network baseline before implementation so modified requirements have a canonical base. Add `NSBluetoothAlwaysUsageDescription` and CoreBluetooth/source inclusion to both build paths and the harness while preserving bundle identity/minimum OS. Do not initialize the real BLE adapter in automated tests.

Implementation order: first validate the signed Mac bundle against a physical GR IIIx with minimal protected reads and the documented write sequence; then complete the fakeable coordinator, UI/history, and regression suite. If no hardware is available, code work can proceed after leaving explore mode, but the Bluetooth path must remain clearly experimental and hardware tasks remain incomplete. Never describe fake/emulator tests as radio validation.

## Risks / Trade-offs

- External success reports do not resolve model/firmware/host differences; capture exact hardware results and retain manual Wi-Fi access.
- The wake command may start camera electronics without capture mode or lens extension; UI says Preparing camera, not Ready to shoot.
- BLE release may affect AP lifetime; its behavior is a hardware acceptance criterion.
- Joining the camera disrupts the Mac's current network; the selected target and progress make that deliberate, while cancellation is not a network rollback.
- System pairing prompts and authorization vary with signing and OS; test the actual bundle and both rebuild/relaunch behavior.

## Open Questions

No unresolved product choice blocks this proposal. Hardware must establish whether the intended GR IIIx/macOS combination accepts protected pairing and WLAN writes, whether BLE can be released safely, and the measured timing limits. Record results before promoting automatic wake from experimental support.
