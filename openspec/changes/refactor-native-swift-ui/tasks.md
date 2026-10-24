## 1. Capture the compatibility baseline

- [x] 1.1 Inspect the current working tree and active Bluetooth/selection changes, record delivered behavior and outstanding hardware checks in this change's `validation.md`, and preserve unrelated edits/artifacts.
- [x] 1.2 Run the existing fixture suite, `make build`, and `./build.sh`; record outcomes, supported minimum window sizes, and representative browser/Settings/preview screenshots before refactoring.
- [x] 1.3 Map existing service and UI assertions to the native requirements, including selection behavior actually present at implementation start; add focused regression coverage only for uncovered operation/admission or migration risks.

## 2. Extract services and normal compilation

- [x] 2.1 Move app bootstrap/window ownership, preferences/models, Wi-Fi/location/credentials, HTTP verification, connection coordination, and downloads into focused Swift sources without changing behavior; keep the existing Bluetooth boundaries.
- [x] 2.2 Introduce one shared build helper/source manifest for target, source inputs, frameworks, and module cache; make the Makefile, bundle builder, and test runner consume it while retaining their entry points and signing/packaging behavior.
- [x] 2.3 Convert test top-level bodies to callable suites with shared helpers and an explicit `tests/main.swift` driver; remove source splitting and concatenation of app text from `tests/run-tests.py`.
- [x] 2.4 Run all existing tests and both build paths after extraction, checking unchanged bundle identity, preference records, and fake-radio test defaults before changing presentation.

## 3. Typed state and presentation-independent operations

- [x] 3.1 Add typed connection targets, connection/download phases, settings/device snapshots, and operation-tagged events; adapt the current web UI temporarily at a boundary rather than retaining dictionaries throughout services.
- [x] 3.2 Introduce macOS 13.3-compatible main-actor observable presentation models; derive control availability and labels from native lifecycle state while preserving independent service admission checks.
- [x] 3.3 Extract passive network/device discovery from connection orchestration with injected access/clock/scheduling and preserved authorization, scan throttling, current-network observation, and no-wake behavior.
- [x] 3.4 Extract session health monitoring while retaining coordinator ownership of session invalidation, stable/late SSID learning, Forget revisions, and stale-response suppression.
- [x] 3.5 Extract the download service from WebKit and window/picker ownership; add a presentation-owned injectable folder chooser, reserving operation admission before the picker and preserving file/format/destination snapshots.
- [x] 3.6 Centralize camera URL construction and User-Agent while preserving distinct verification, image, and original-download session/delegate/timeout policies; cover encoded names and invalid relative paths.
- [x] 3.7 Preserve serialized blocking operations, attempt/link generations, cancellation/draining, credential clearing, sleep handling, sequential transfers, ZIP validation, exclusive publication, and partial-save accounting; run the corresponding service regression suites.
- [x] 3.8 While the browser remains web-based, implement cancellable scheme tasks with stopped-callback suppression and safe text/encoded image paths; verify cancellation and punctuation cases through the temporary adapter.
- [x] 3.9 Remove fields/helpers made redundant by the typed model and extraction only after checking their consumers and tests; verify the temporary web UI still works at this checkpoint.

## 4. Native Settings checkpoint

- [x] 4.1 Build a SwiftUI Settings form hosted in the existing AppKit modal panel, with native folder/format controls, separate Bluetooth/network lists, discovery/setup guidance, and accessible Forget actions.
- [x] 4.2 Preserve one reusable modal, visible close button, Command-comma/menu opening, Command-W/Escape dismissal, focus restoration, screen-constrained sizing, and usable scrolling at 400 by 360 points.
- [x] 4.3 Attach the folder picker to Settings, prevent parent closure while its sheet is attached, and verify preference changes and an actual fixture download complete while Settings is modal.
- [x] 4.4 Replace Settings DOM tests with native model/host-window checks for persistence, invalid records, independent Forget behavior, accessibility, narrow/long-list layout, keyboard handling, and reopening; remove `SETTINGS_HTML` and Settings-specific web lifecycle/measurement code after parity passes.

## 5. Camera image pipeline

- [x] 5.1 Implement a fakeable image loader with session-generation/photo/rendition keys, identical-request coalescing, two-request default concurrency, preview priority, and demand cancellation.
- [x] 5.2 Add thumbnail downsampling and a decoded-cost memory cache with a 64 MiB default limit; invalidate session-scoped work/cache and discard stale responses on disconnect or library replacement.
- [x] 5.3 Cover injected concurrency/cache bounds, coalescing, preview priority, cancellation, stale matching filenames after reconnect, malformed image responses, placeholders, and bounded retry behavior using local fixtures.

## 6. Native browser, gallery, and progress checkpoint

- [x] 6.1 Host a native SwiftUI main view in the AppKit window with grouped route-aware target picker, adjacent Find cameras, primary lifecycle action, Settings, status, manual recovery, and a usable 480 by 360 point layout.
- [x] 6.2 Add lazy grid/list presentation keyed by directory and filename, stable selection/active-photo state, checkbox/bulk actions, selected counts, and ordered batch requests; selection changes must reuse loaded images rather than restarting requests.
- [x] 6.3 Port Finder-style selection/focus/range behavior and its scenarios only if that separate feature has landed; otherwise preserve the existing interaction baseline and document the independent feature status without implementing it here.
- [x] 6.4 Add native preview with previous/next, filename/position, Escape, full-resolution download, focus return, and keyboard handling scoped away from unrelated controls and modals.
- [x] 6.5 Add a shared accessible progress presentation above preview, preserving measured/unknown-length progress, stage labels, operation snapshots, stale-event rejection, terminal outcomes, and duplicate-action locks while browsing.
- [x] 6.6 Replace remaining browser DOM assertions with model and actual host-window/responder checks for routes, lifecycle labels, independent BLE/library status, minimum layout, selection, preview, progress, keyboard/focus, and literal camera text.

## 7. Final cutover and verification

- [x] 7.1 Remove `APP_HTML`, remaining WebKit message/event adapters, the custom scheme handler, WebKit imports/linkage, obsolete DOM tests, and temporary dual-presentation code after native parity passes.
- [x] 7.2 Run the complete native/service/fixture suite and both build paths; verify no production service depends on a web view/window and tests compile ordinary app sources without text splitting or application-source concatenation.
- [x] 7.3 Verify existing persisted settings/history in the rebuilt signed app, native Settings during export, minimum-size grid/list/preview layouts, accessibility labels, real keyboard/modifier routing, and rapid scrolling/reconnect behavior; record results and any unverified manual checks.
- [x] 7.4 With hardware when available, smoke-test Current Wi-Fi, remembered-network and experimental Bluetooth handoff routes, thumbnail/preview responsiveness, and an original/ZIP download; record actual model/firmware/macOS evidence separately and leave physical checks explicitly pending if unavailable.
- [x] 7.5 Update README architecture/build/test instructions, document any small native presentation differences, complete `validation.md` with phase outcomes and limitations, run strict OpenSpec validation and diff checks, and confirm no unrelated change artifacts were modified.
