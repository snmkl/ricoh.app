## 1. Native selection model

- [x] 1.1 Add a focused Swift selection-state type owned by `BrowserModel` with selected `CameraPhoto` identities, active photo, anchor, and optional baseline; preserve one authoritative membership set and register any new production source in `swift-build.py`.
- [x] 1.2 Implement inclusive displayed-order range recomputation from a fixed anchor and baseline, preserving independent selections during contraction and reversal across the anchor.
- [x] 1.3 Define origin/session transitions for preview clicks, Command toggles, checkbox toggles, direct keyboard focus, repeated Shift actions, and no-origin initialization; integrate them with existing browser-model methods.

## 2. Native pointer input and presentation

- [x] 2.1 Add one modifier-aware interaction path in `NativeBrowser.swift` for photo cards and list rows, covering thumbnails, labels, padding, and checkboxes with Shift-before-Command precedence and exactly one action per click.
- [x] 2.2 Preserve unmodified preview/checkbox behavior and native accessible actions; add a narrowly scoped AppKit input adapter if needed for event modifiers and nested-control routing on macOS 13.3.
- [x] 2.3 Bind selection presentation and accessible selected state to the model, retain stable image identities, and show a separate active-photo highlight without invalidating image-loader demand or cache.
- [x] 2.4 Coordinate native gallery focus with preview dismissal and direct item focus; distinguish pointer/programmatic restoration from an intentional new origin without stealing focus from other controls.

## 3. Native keyboard navigation and lifecycle

- [x] 3.1 Add gallery-owned Shift+Arrow responder handling with preview/modal/sheet/control guards and additional-modifier exclusions; retain Command-comma and existing preview keyboard behavior.
- [x] 3.2 Share effective column metrics between responsive grid layout and navigation; implement horizontal order, vertical row movement, list movement, incomplete-row clamping, boundaries, and first-photo initialization.
- [x] 3.3 Preserve anchor/baseline across key repeat and Shift release; consume handled navigation, scroll lazy endpoints into view, and restore focus without beginning another session.
- [x] 3.4 Preserve selection, active identity, anchor, and baseline across grid/list changes and use current geometry after resizing.
- [x] 3.5 Integrate complete selection-state resets with `BrowserModel.clearLibrary()` and photo replacement; guard empty libraries and missing identities.
- [x] 3.6 End range sessions on Clear and Select all/Deselect all while retaining valid active identity; preserve displayed-order `selectedFiles` and existing download snapshots, progress, and admission guards.

## 4. Model and native interaction regression coverage

- [x] 4.1 Add callable selection-model tests in `tests/SelectionTests.swift`, register them in `tests/main.swift`, and reuse native fixture helpers without web views or source concatenation.
- [x] 4.2 Exercise actual native Command-click events over thumbnail, label, padding, and checkbox in both views; verify one-action toggling, combined-modifier precedence, accessible actions, and preview suppression.
- [x] 4.3 Cover forward/backward and cross-directory Shift-click ranges, duplicate basenames, missing origins, repeated endpoint changes, and independent baseline selections.
- [x] 4.4 Cover Shift+Arrow extension, contraction, anchor crossing, baseline overlap, Shift release/repress, direct keyboard origins, key repeat, and return from preview using both model transitions and host-window responder events.
- [x] 4.5 Cover multiple grid widths, incomplete final rows, list navigation, library boundaries, view changes during a range, lazy endpoint scrolling, and visible/accessibility focus; assert unchanged loaded-image request counts and generation.
- [x] 4.6 Verify control/editable/preview/modal/sheet exclusions, Command-comma, plain preview clicks, checkbox toggles, bulk actions, empty libraries, and disconnect/reconnect resets.
- [x] 4.7 Verify selected counts and ordered download requests, then change selection during an active fixture export and assert its captured files, progress, and disabled actions are preserved.

## 5. Documentation and validation

- [x] 5.1 Document Command-click, Shift-click, Shift+Arrow, range adjustment, and retained plain-click preview behavior in `README.md`.
- [x] 5.2 Run `python3 tests/run-tests.py`, `make build`, and `./build.sh`; fix selection-related failures, run strict OpenSpec/diff checks, and record results or unrelated blockers.
- [x] 5.3 Manually verify physical modifier clicks, key repeat/reversal, focus return, grid/list switching, resizing, and offscreen endpoint scrolling in the native app; record results and any unverified checks.
