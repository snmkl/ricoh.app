## Why

The app already performs camera communication, downloads, and platform integration in Swift, but embedded HTML introduces a second state system, string-based messages, and manual window/layout coordination. Separating those services and migrating presentation to SwiftUI will make subsequent changes easier to reason about while retaining the tested camera and export behavior.

## What Changes

- Extract preferences, platform adapters, camera HTTP access, connection orchestration, downloads, and presentation from `GRBrowser.swift` into focused Swift sources with explicit dependencies.
- Introduce typed connection targets, lifecycle states, settings snapshots, and download events; keep one authoritative native owner for each operation and derive action availability from that state.
- Separate download execution from message parsing, folder-picker presentation, and progress rendering. Preserve sequential transfers, frozen operation inputs, atomic non-overwriting publication, and failure recovery.
- Replace HTML settings with native SwiftUI controls hosted in the existing macOS modal window, then migrate the main toolbar, gallery/list, preview, and progress presentation. Remove both WebKit views, their message bridges, embedded HTML/CSS/JavaScript, and the custom image URL scheme after parity is verified.
- Add bounded, cancellable thumbnail/preview loading with stable photo identities and safe URL construction. Selection changes update presentation without rebuilding/reloading the library's thumbnails.
- Consolidate build inputs and compiler/framework configuration, and compile tests against the actual core sources instead of splitting Swift source at a comment.
- Keep macOS 13.3, the existing app identity and preferences, current connection/recovery semantics, and current selection interactions. Preserve any Finder-style selection behavior delivered by the separate `add-finder-style-image-selection` change before migration; this change does not introduce those gestures.

## Capabilities

### New Capabilities

- `native-camera-browser`: Native browser presentation, authoritative UI state, stable gallery/preview identity, bounded image loading, and parity during the migration away from WebKit.

### Modified Capabilities

- `app-settings`: Require native form controls within the existing modal Settings window; retain standard close/keyboard behavior and remove the redundant HTML form Close-control requirement.

Camera-network, Bluetooth, download-progress, and separately proposed photo-selection behavior are compatibility contracts, not new features in this change.

## Impact

- `GRBrowser.swift`, the three Bluetooth sources, `main.swift`, and new focused service/model/UI files; maintain the existing fakeable platform boundaries and radio safeguards.
- `Makefile`, `build.sh`, and `tests/run-tests.py` gain shared build configuration/source discovery. Native model and AppKit/SwiftUI integration checks replace WebKit-specific assertions while retaining existing service and fixture coverage.
- Remove WebKit linkage when the last web view is removed; add SwiftUI with no third-party runtime dependency. Preserve the signed bundle identity, `Info.plist` permissions, persisted record formats, and application installation behavior.
- Update README architecture and development/test instructions. Physical camera checks remain distinct from automated fixture results and do not promote experimental Bluetooth support.
- Coordinate with the active Bluetooth and Finder-style selection changes without editing or archiving their artifacts as part of this proposal.
