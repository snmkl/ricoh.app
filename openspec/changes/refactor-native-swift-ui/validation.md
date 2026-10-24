# Native SwiftUI migration validation

## Environment and scope

Implementation session: 2026-10-22. Host: Apple Silicon, macOS 26.6.2, Apple Swift 6.4, SDK 27.0. Both compiled outputs retain a macOS 13.3 minimum (`LC_BUILD_VERSION`). Running on macOS 13.3 itself was not exercised.

The working tree initially contained only untracked artifacts for this change and `add-finder-style-image-selection`; tracked sources were clean. Bluetooth software was already implemented, while that change's physical checks 1.2–1.4 remained incomplete. No Bluetooth or selection artifacts were modified here. `Info.plist`, `CameraBluetooth.swift`, and `CoreBluetoothTransport.swift` also remain unchanged.

Finder-style selection has not landed. This migration preserves plain-click preview, checkbox toggles, Select all/Clear, displayed-order exports, and grid/list membership. It does not introduce Command/Shift range selection.

## Baseline and extraction

- The original complete fixture suite, `make build`, and signed `./build.sh` bundle build passed.
- Minimum sizes: main window 480 × 360 points; Settings 400 × 360 points.
- Representative baseline WebKit captures remain in `build/baseline-browser.png`, `build/baseline-settings.png`, and `build/baseline-preview.png`.
- Behavior-preserving extraction passed the same suite and both build paths before native presentation changes (`build/extraction-tests.log`, `build/extraction-make.log`, `build/extraction-bundle.log`). Bundle identity, preference formats, and fake-radio defaults were unchanged.
- The build/test entry points now share `swift-build.py`. Tests compile ordinary application files with callable suites, shared helpers, and `tests/main.swift`; no application-source splitting or concatenation remains.

## Service compatibility and coverage map

| Area | Retained or added regression coverage |
| --- | --- |
| Downloads | Sequential originals; measured and unknown-length progress; ZIP contents/validation; HTTP/truncation/staging/archive/save errors; cleanup; exclusive collision publication; partial-save counts; duplicate/picker admission; captured files/format/destination; terminal recovery |
| Preferences | Existing `settings.v1` and `bluetooth-cameras.v1` formats; defaults; corrupt records; bookmarks/moves; independent network/device history and Forget |
| Connection | Saved macOS/app/manual credential fallback and cancellation; exact SSIDs; discovery authorization/throttling/late arrival; current-network observation; readiness and verification retries; stale attempts; serialized association/drain; sleep; late SSID learning; Forget revisions; stale health callbacks |
| Bluetooth | Documented GATT sequence and strict values; computer name; unsupported/rejected/disconnected setup; injected clocks; ephemeral credentials; identity mismatch; passive no-wake discovery; presence expiry; independent BLE release and verified-library state |
| Native presentation | Typed snapshots/events; service-derived admission and lifecycle labels; routes and manual recovery; literal camera text; stable selection and image reuse; minimum header accessibility frames; preview responder/focus; shared progress; modal Settings, shortcuts, sheets, reopening and exports |
| Images and URLs | Encoded punctuation; invalid relative paths rejected before transfer/publication; generation/photo/rendition keys; coalescing; queue priority; concurrency; cancellation acknowledgement; downsampling; decoded-cost eviction; malformed data and bounded renewed-demand retries |

### Typed service checkpoint

The complete original suite passed through the temporary web adapter (`build/typed-tests.log`). Added URL-punctuation, literal-text and stopped-scheme-callback checks also passed before the adapter was removed.

`CameraConnection` remains the admission/session/history owner. `CameraDiscovery` performs passive observation through injected Wi-Fi, authorization, radio, worker and clock boundaries. `SessionHealthMonitor` reports observations; the coordinator retains invalidation and late-history decisions. `DownloadService` uses typed progress and an injected destination chooser without any web view or window dependency.

Blocking platform/filesystem work remains serialized. Attempt/link generations, credential clearing, association drain, stale suppression, archive validation, exclusive publication and partial saves retain their regression checks.

### Native Settings checkpoint

The full service/temporary-browser/native-Settings suite passed (`build/native-settings-tests.log`), followed by focused accessibility checks (`build/native-settings-focused.log`). The harness needed normal AppKit launch initialization for SwiftUI's accessibility tree; the final driver runs within an actual AppKit application event loop.

Native checks cover persisted folder/format, labeled controls and Forget actions, standard title-bar close, the production Command-comma menu, Command-W/Escape, one reusable modal, screen constraints, attached-sheet closure protection, 400 × 360 content with 32 network rows, independent Forget, and a real two-original fixture export completing while Settings changes format. Settings HTML and JavaScript lifecycle/measurement code were then removed.

### Image pipeline checkpoint

Focused checks passed (`build/image-tests.log`). Defaults are two simultaneous requests and 64 MiB of decoded cache cost. Injected bounds verify coalescing, preview queue priority, LRU eviction, thumbnail downsampling, old matching filenames after reconnect, queued/active cancellation, malformed data, and renewed-demand retry without an automatic loop.

Retired transfers retain their scheduler slots until cancellation acknowledgement. Decoding runs off the main thread. Original transfers retain their separate delegate and timeout policy.

### Native browser and final cutover

Native host checks passed before the web browser was removed (`build/native-browser-tests.log`). The final suite covers the following through ordinary application sources:

- Current Wi-Fi/Bluetooth routing, explicit target selection without waking, CONNECT/CANCEL/CANCELLING/DISCONNECT, independent released BLE/library readiness, and manual recovery.
- Actual accessibility frames for a single-line header at 480 points; grid/list membership; distinct duplicate basenames; literal punctuation; selection-only updates without new loaded-thumbnail requests.
- Actual `NSWindow.sendEvent` routing for preview Left/Right/Escape, exclusion of a different native text-field responder, and usable gallery focus after dismissal. OS foreground activation is unavailable in this environment, so these are host/responder events rather than physical keyboard evidence.
- Shared accessible progress above preview, measured/unknown-length events, browsing during export, stale terminal rejection, captured requests and format before a picker, duplicate picker/connection bypass rejection, and a stale original-download action after disconnect.
- Library invalidation clears selection/active/preview/image generations. Image click explicitly restores preview keyboard ownership without global key interception.

The final code contains no WebKit imports, embedded HTML, JavaScript evaluation/message adapters, custom scheme handler, or dual UI. The signed binary's direct linkage was inspected and contains no WebKit dependency. Production services have no presentation-window dependency.

## Final automated results

| Check | Outcome |
| --- | --- |
| `python3 tests/run-tests.py` | Passed, 39 reported PASS groups; `build/native-final-tests.log` |
| `make build` | Passed; `build/native-final-make.log` |
| `./build.sh` | Passed, staged bundle/icon packaging and ad-hoc signing; `build/native-final-bundle.log` |
| `codesign --verify --strict build/GRBrowser.app` | Passed |
| Bundle identity / minimum OS | `local.GRBrowser` / 13.3 preserved |
| Strict OpenSpec validation | Passed |
| Diff whitespace and unrelated-artifact checks | Passed |

The build helper retains the embedded plist for the development binary and the existing staged bundle/signing/install behavior. Bootstrap explicitly retains the AppDelegate throughout the run loop. README now documents the architecture, shared builds, native interactions, image policy and experimental Bluetooth status.

Sandbox access requirements observed during validation: localhost socket binding, `iconutil`, and the SwiftUI compiler macro process need execution outside this sandbox. Re-running with that access passed; these were environment restrictions, not fixture failures.

## Pending manual and physical validation

These limitations are recorded explicitly; automated results do not imply the checks below passed. Tasks 7.3/7.4 include recording unverified manual checks and unavailable hardware, so their implementation bookkeeping is complete with this evidence outstanding.

- [ ] Inspect existing production-domain preferences/history in the rebuilt signed app. Isolated persistence/corruption tests passed; no production records were migrated or intentionally changed.
- [ ] Visually inspect grid/list/preview at minimum sizes and Settings with long lists, and navigate with VoiceOver. Native accessibility labels/frames were checked programmatically. AppKit bitmap caching produced blank SwiftUI captures on this host; those images are not visual evidence and are no longer generated by the suite.
- [ ] Exercise physical keyboard/modifier input, focus restoration after unrelated controls/Settings, rapid scrolling, and repeated reconnects in the signed app. Computer Use reported that permissions are not granted, so this session could not perform the OS-level visual/input check.
- [ ] Verify Current Wi-Fi, remembered-network association, experimental Bluetooth pairing/handoff/release, thumbnail/preview latency, and original/ZIP downloads on a physical camera. No physical camera was supplied or identified for this session.
- [ ] Record physical camera model, firmware, macOS, pairing/relaunch behavior, AP stability and stage timings when hardware is available. Camera model/firmware values in automated tests are fixtures only; no physical model or firmware result is claimed here.

Bluetooth support remains experimental. The independent Bluetooth and Finder-selection change artifacts remain intact and unarchived.
