## Why

Selecting many camera photos currently requires hitting each photo's checkbox or selecting the entire library. With the native SwiftUI gallery now delivered, familiar macOS modifier gestures can make it faster to build and adjust batches directly from the images in either gallery view.

## What Changes

- Support Cmd+Click anywhere on a photo card to toggle that photo's selection without opening its preview or disturbing other selected photos.
- Support Shift+Click to add the inclusive range between an anchor photo and the clicked photo, following the displayed photo order.
- Support Shift+Arrow in the gallery to extend or shrink the active range from the highlighted or last-clicked photo, with grid-aware vertical movement and stable behavior when direction reverses.
- Keep an identifiable keyboard highlight and preserve it across selection updates and grid/list switches; reset navigation state when the library changes.
- Preserve plain-click preview, checkbox toggles, selection counts, Select all/Clear, and the existing download behavior.

## Capabilities

### New Capabilities

- `photo-selection`: Whole-card modifier selection, anchored ranges, keyboard range adjustment, focus feedback, and selection lifecycle in grid and list views.

### Modified Capabilities

None. Existing download, settings, and camera-network requirements remain unchanged.

## Impact

- Implementation follows `refactor-native-swift-ui`, delivered in commit `278027e`. Its native gallery and ordinary Swift test compilation are the baseline; this change does not require another UI migration.
- `BrowserModel.swift` and a focused Swift selection-state type: selected membership, active photo, anchor, range baseline, and library reset behavior.
- `NativeBrowser.swift`: Whole-card modifier routing, gallery keyboard ownership, layout-aware navigation, focus feedback, accessibility, and endpoint scrolling, retaining macOS 13.3 support.
- `tests/SelectionTests.swift`, `tests/NativeBrowserTests.swift`, and `tests/main.swift`: Selection-model and native host-window/responder coverage using the existing fixtures and image loader; register any new production source in `swift-build.py`.
- `README.md`: Document the selection shortcuts and the existing preview interaction.
- No camera API, download-service, image-pipeline policy, persisted-data, or external dependency changes are required. Native image identities, loaded-image reuse, operation admission, and frozen download requests remain compatibility requirements.
