## Context

The native UI migration is delivered in commit `278027e` (`refactor-native-swift-ui`). `GRBrowser.swift`, embedded HTML, and WebKit are gone. This change targets that committed architecture and remains a separate, unimplemented feature.

`BrowserModel.swift` owns ordered `photos`, `selected`, `active`, and `preview` state on the main actor. `CameraPhoto` identifies a photo by its exact directory and filename. `toggle`, `selectAll`, and `clearSelection` provide current selection behavior; `selectedFiles` preserves display order. `clearLibrary()` clears library state and invalidates image generations on connection changes.

`NativeBrowser.swift` renders a `ScrollView` containing `LazyVGrid` or `LazyVStack`, with preview buttons, checkbox toggles, `@FocusState`, and `ScrollViewReader`. Grid columns currently adapt to a 145-point minimum with 10-point spacing and 12-point gallery padding. A local AppKit `PreviewKeyResponder` owns preview keyboard input. `CameraImageLoader` already preserves loaded images across selection-only updates. Tests compile ordinary application sources through `swift-build.py` and run inside an AppKit event loop with actual host windows.

## Goals / Non-Goals

**Goals:**

- Support whole-card Command toggling and anchored Shift ranges in both native views.
- Make Shift+Arrow extend, contract, and reverse a range while preserving independent selections.
- Keep the active photo visible, keyboard reachable, and distinguishable from selected membership.
- Preserve native preview, checkbox/bulk actions, image reuse, download admission, and macOS 13.3 compatibility.

**Non-Goals:**

- Reintroducing a web gallery, repeating the native migration, or adding a second source of selection truth.
- Drag selection, sorting, every Finder shortcut, or changing plain-click preview to double-click preview.
- Replacing the gallery with an AppKit collection view without evidence that a focused input adapter is insufficient.
- Changing camera communication, persistence, image-loading policy, or export behavior.

## Decisions

### 1. Model range selection as testable Swift state

Introduce a small value-type selection model, owned by `BrowserModel`, for selected `CameraPhoto` values, optional active photo, optional anchor, and a nullable range-session baseline. Keep one authoritative selected set; expose existing `selected`, `active`, and `selectedFiles` behavior through the browser model rather than maintaining parallel membership in views. Register a new production file in `swift-build.py` if the type is extracted.

Resolve identities against the current ordered `photos` collection. For baseline `B`, anchor `a`, and endpoint `e`, compute:

`selection = B ∪ inclusiveDisplayedRange(a, e)`

Recompute from the unchanged baseline on every range adjustment. Reversal removes only photos added by that range, including when crossing the anchor. Baseline photos remain selected even when inside a contracted interval. Releasing Shift alone retains the session, allowing later Shift+Arrow presses to shrink it.

A plain preview click, Command toggle, unmodified checkbox toggle, or direct keyboard focus on another photo establishes a new origin and ends the previous session. Shift actions retain the anchor and update the endpoint. Pointer focus before a modified click and focus restoration during selection updates must not replace the origin. With no valid origin, Shift-click selects the clicked photo; the first Shift+Arrow selects the first displayed photo only. Both preserve existing membership as their baseline.

**Alternative considered:** Tracking only the last index or incrementally adding traversed photos cannot distinguish baseline membership from range additions and therefore cannot reliably shrink. Keeping this logic in view-local state would make lifecycle resets and model tests harder.

### 2. Dispatch native pointer input once per card

Use a shared, typed interaction path for thumbnail, filename, directory text, card padding, and checkbox input in grid and list views. Capture modifiers from the originating native event. Dispatch Shift first, Command second, then the existing unmodified action. Command-Shift-click performs range selection. Command toggles membership; modified clicks never open preview. An unmodified checkbox toggles once; an unmodified preview target retains plain-click preview. Control-click is not Command selection.

The current separate preview `Button` and checkbox `Toggle` paths must cooperate with whole-card handling so parent and child do not both act. Use a narrowly scoped AppKit-backed input adapter where needed to preserve modifier information and reliable hit routing on macOS 13.3. Retain native accessible preview and checkbox actions for keyboard/assistive activation. Avoid an opaque overlay that makes these controls unreachable, and avoid application-wide mouse/key interception.

**Alternative considered:** Adding an independent parent tap gesture to the existing controls risks duplicate toggles and losing modifier information. A collection-view rewrite is substantially larger than the input boundary this feature needs.

### 3. Keep keyboard ownership local to the gallery

Extend native gallery focus with a local responder/input adapter, using the existing preview responder as the integration pattern. Handle Shift+Arrow only when gallery input owns the responder, preview is closed, there is no modal or attached sheet, and Command/Option/Control are absent. Pass all other input through normally. Keep Command-comma and existing preview Left/Right/Escape handling intact.

Keep the logical active photo in the selection model and actual keyboard ownership in the native focus layer. Gallery entry and return from preview restore the valid active item without opening preview or resetting the range session. Direct keyboard focus on another item establishes a new origin. Rendering updates must not repeatedly claim first responder or steal input from toolbar controls, editable fields, Settings, or sheets.

Show a distinct active outline in addition to selected membership. Expose selected state and meaningful item labels through native accessibility. Use `ScrollViewReader` to reveal the endpoint with minimal scrolling and focus it when realized, including lazy items initially offscreen. Consumed navigation suppresses default scroll movement; unhandled events retain normal responder behavior. A focus callback produced by this action must not begin another session.

**Alternative considered:** A global key monitor can intercept other controls and modals. Newer SwiftUI keyboard APIs cannot be assumed because the deployment target remains macOS 13.3.

### 4. Share grid metrics between layout and navigation

Use one source of truth for available gallery width, padding, spacing, and effective column count. Feed that count into both grid construction and navigation, retaining the current tile sizing. Do not depend on measuring every cell: lazy layout does not realize all photos, yet navigation must reach offscreen endpoints. Recompute metrics after resize and when changing view.

In grid view, Left/Right move one photo in display order, including across row boundaries; Up/Down move one row in the same column. A move into a short final row clamps to that row's last photo. Moves outside the first/last row or library keep the endpoint unchanged. In list view, Left/Up mean previous and Right/Down mean next. Select the inclusive linear interval between origin and destination, rather than a rectangle, and never wrap around the library.

**Alternative considered:** A hard-coded stride fails on resize. An independent estimate of adaptive columns can disagree with layout; shared metrics avoid that discrepancy.

### 5. Preserve lifecycle, images, and download boundaries

Integrate selection reset with `BrowserModel.clearLibrary()` and every photo replacement path, clearing active, anchor, and baseline along with membership. Guard empty libraries and missing identities. Grid/list switching preserves all valid range state. Clear and Select all/Deselect all end the session and clear its anchor while retaining any valid active photo; the next range starts there using the post-action membership as its baseline.

Keep stable `CameraPhoto` and `CameraImageKey` identities. Selection/focus updates must not invalidate `CameraImageLoader`, advance its library generation, replace the photo collection, or restart unchanged loaded-image requests. SwiftUI is free to reevaluate view values; concrete view-instance identity is not a requirement. Existing caching, concurrency, and lifecycle cancellation remain authoritative.

Continue deriving selected requests in displayed order through `selectedFiles`. Selection can change during an active download, but `DownloadService` retains its captured files/format/destination, progress, and admission guards. No download-service change is needed.

### 6. Test the model and actual native input separately

Add `tests/SelectionTests.swift` with a callable suite registered in `tests/main.swift`; the existing build helper already discovers test Swift files. Test range transitions directly with fixed `CameraPhoto` arrays, including duplicate basenames, baseline overlap, repeated Shift actions, reversal, boundaries, bulk actions, and library resets.

Extend the native browser host tests with real window/responder mouse and keyboard events against actual card regions and checkbox controls. Cover modifier precedence, exactly-once routing, focus return, exclusion of controls/modals/sheets, multiple grid widths, list switching, lazy endpoint scrolling, and visible/accessibility selection state. Direct model calls alone do not establish that native event routing works.

Use the existing fake image transport to assert no new requests or generation changes for unchanged loaded thumbnails. Reuse download fixtures to assert ordered request keys, captured file lists, progress, and disabled actions while selection changes. Run `python3 tests/run-tests.py`, `make build`, and `./build.sh`; manually verify physical modifier input, key repeat/reversal, focus, and scrolling. Record unavailable manual checks honestly. Document shortcuts in README.

## Risks / Trade-offs

- [“Finder-style” leaves edge cases open to interpretation] → Keep the exact supported gestures in `photo-selection/spec.md`, including this app's plain-click preview behavior.
- [Nested native controls consume modifiers or act twice] → Use a shared input dispatcher and test actual pointer events over both parent and child regions.
- [Focus restoration silently resets the anchor] → Distinguish direct focus movement from pointer/programmatic restoration and test repeated range events.
- [Lazy layout prevents targeting an unrealized photo] → Use shared grid metrics and stable identities, then scroll and focus when the endpoint is realized.
- [SwiftUI updates restart image demand] → Retain stable image keys/cache state and assert transport request counts rather than concrete view identity.
- [Selection input breaks previews, Settings, or sheets] → Scope handling to gallery responder ownership and preserve existing modal/control guards.

## Migration Plan

The prerequisite native migration is already committed as `278027e`; no new migration work or circular dependency is introduced. Implement this feature against its native model, presentation, image loader, and test harness. No persisted data changes or external dependencies are required. Reverting this feature restores the native checkbox/bulk-selection baseline without changing preferences or downloaded files. Keep this change active until its own implementation and checks are completed; artifact readiness alone is not implementation completion.

## Open Questions

None blocking. Native host tests will establish whether SwiftUI controls plus a small AppKit input adapter meet the routing/focus requirements; any broader collection-view change requires evidence of a concrete limitation first.
