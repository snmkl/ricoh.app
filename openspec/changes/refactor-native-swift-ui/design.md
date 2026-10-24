## Context

The current app has 3,088 lines of Swift source, including approximately 680 lines of embedded HTML/CSS/JavaScript. `GRBrowser.swift` contains most platform services and presentation. `CameraConnection` already has injectable Wi-Fi, credentials, camera, Bluetooth, clock, and scheduler boundaries; `DownloadHandler` already protects staging, sequential transfers, preference snapshots, and exclusive destination publishing. Existing tests exercise these behaviors through local HTTP fixtures, fake radios, and real WebKit windows.

The migration must retain macOS 13.3, command-line builds, `local.GRBrowser`, `settings.v1`, and `bluetooth-cameras.v1`. The active Bluetooth change records implemented software and outstanding physical checks. A separate, unimplemented `add-finder-style-image-selection` change defines modifier/range gestures. Neither change is archived or rewritten here.

## Goals / Non-Goals

**Goals:**

- Make services usable and testable without a web view or presentation window.
- Keep one authoritative native lifecycle for connections and downloads, using typed data at service and presentation boundaries.
- Replace both web views with native SwiftUI presentation while preserving observable behavior, minimum window usability, keyboard access, and export correctness.
- Preserve stable photo identities and load images with explicit concurrency, cache, and cancellation policies appropriate for slow camera Wi-Fi.
- Replace source-text test assembly and duplicated build configuration with ordinary Swift compilation against shared source inputs.

**Non-Goals:**

- New camera endpoints, changed pairing/wake behavior, automatic reconnect, restoration of the Mac's previous network, or promotion of experimental Bluetooth support.
- New selection gestures, a broad visual redesign, new export formats, an iOS port, or raising the minimum OS.
- A blanket concurrency rewrite, a generic state-management framework, third-party runtime dependencies, or a mandatory Xcode project/Swift package migration.

## Decisions

### 1. Extract boundaries before replacing presentation

Organize sources by responsibility: app bootstrap/window ownership; preferences and persisted models; Wi-Fi/location/Keychain adapters; camera HTTP access; connection coordination/monitoring; download/export execution; image loading; and SwiftUI views/presentation models. Keep the existing Bluetooth protocol/transport split.

Use focused types rather than one replacement application controller that owns everything. `CameraConnection` remains the attempt/session admission owner. Extract passive discovery and session health responsibilities behind small injected boundaries, retaining coordinator ownership of admission and terminal transitions. First move code without semantic changes; then change interfaces under existing tests.

Alternative: only split the large file. This improves navigation but leaves WebKit-dependent services and duplicated state intact. Alternative: rewrite all services with the UI. This combines radio, disk, and presentation risk in one step.

### 2. Use typed native state with explicit ownership

Define `ConnectionTarget` cases for Current Wi-Fi, exact remembered network identity, and Bluetooth UUID. Replace lifecycle string literals with enums, and dictionary snapshots/events with structs carrying operation/session identity. Keep presentation text separate from phase identity. Retain distinct attempt, verified session, BLE link, discovery generation, history revision, and draining concepts rather than collapsing them into a single busy Boolean.

Use `@MainActor` presentation models conforming to `ObservableObject`, with `@Published` values and `@StateObject` ownership for macOS 13.3 compatibility. Keep gallery selection/preview state local to its presentation model. Derive enabled actions and primary-action labels from connection/download state; the services independently enforce the same admission policy. Views never own an alternative connection/download lifecycle.

Keep blocking CoreWLAN, Keychain, filesystem, and archive work off the main thread on the existing serialized execution boundaries. Add actor isolation incrementally where delegate entry points can safely hop to it. Retain generation checks across all queue/actor hops. Short sequential helper operations can adopt async APIs after equivalent cancellation tests pass; converting the whole radio workflow is not required.

Alternative: retain `[String: Any]` as the internal model. This preserves runtime casting and UI-specific serialization. Alternative: adopt newer Observation APIs. This would require changing the deployment target.

### 3. Detach download execution from presentation

Extract `DownloadService` with typed request/progress/outcome values and no WebKit, JavaScript evaluation, window, or folder-picker ownership. The presentation coordinator resolves a destination through an injected folder-picker boundary. Preserve admission immediately on acceptance, before presenting a picker, so a second action cannot open another picker or transfer.

Freeze files and format at acceptance and destination before transfer, even if Settings changes during a picker or operation. Preserve the current sequential download delegate, temporary-file lifetime rules, complete staging before publication, ZIP validation, partial-save accounting, and atomic exclusive rename behavior. Keep progress delivery on the main thread and reject events from a prior operation.

Use a short-lived adapter for the old WebKit message/event protocol during the transition. Remove it after native parity; do not keep two permanent UIs or two download implementations.

### 4. Migrate Settings first, retaining the modal contract

Host a SwiftUI Settings form in the existing AppKit-owned modal panel with `NSHostingView`. Use native folder display/chooser, export-format picker, Bluetooth and network lists, accessible removal actions, errors, and discovery/setup guidance. Retain the standard close button, Command-W, Escape, Command-comma/menu entry, one reusable window, and attached folder-picker sheet protection.

Use native layout constraints and scrollable device lists rather than measuring DOM height through JavaScript. Preserve the 400-point Settings minimum width and 360-point minimum height; constrain initial size to the screen. Continue model, connection, and download updates during the modal. Restore focus to the invoking control when practical and to the browser otherwise.

Alternative: use a standalone SwiftUI Settings scene. That would change the existing modal behavior. Native controls within the current window remove the WebKit coordination without coupling this refactor to a product change.

### 5. Native browser with stable photo identity

Host the main SwiftUI view in the existing AppKit main window. Preserve the connection picker grouping and explicit target semantics, route icon, adjacent Find cameras action, connect/cancel/drain/disconnect behavior, Settings entry, grid/list switch, selection actions, empty/error states, preview navigation, and full-resolution download action. Keep the main minimum at 480 by 360 points and the compact single-line connection header.

Use `ScrollView`/`LazyVGrid` and a lazy list layout keyed by exact camera directory plus filename. These keys distinguish duplicate basenames. Keep display order explicit. Selection updates change membership/focus state without clearing image state; view switches retain valid selection and preview identity. Library replacement or disconnect invalidates the gallery state and its image generation.

Implement preview as an overlay in the main presentation hierarchy, with the shared download indicator above it so progress remains visible. Scope Left/Right/Escape to preview and gallery input appropriately; do not intercept unrelated selectors, fields, Settings, or sheets. Preserve the existing visual identity where practical without reproducing every CSS detail.

At implementation start, record the actual selection baseline. If `add-finder-style-image-selection` has landed, port its selection model and full gesture/focus scenarios to the native views. If it has not, retain existing plain-click preview, checkbox toggle, bulk selection, and ordered batch requests. Do not silently add or drop that separate feature, or edit its proposal in this change. Reconcile overlapping source changes when integration occurs.

Alternative: retain a web gallery after native Settings. This is an intermediate checkpoint, but the final result still pays bridge and scheme-handler costs. Alternative: start with a custom AppKit collection view. Reserve that fallback for demonstrated SwiftUI interaction/performance limitations rather than adopting its additional plumbing in advance.

### 6. Explicit camera image pipeline

Centralize endpoint URL construction and User-Agent in a small camera API boundary shared by verification, image loading, and downloads. Keep distinct sessions/configurations where verification timeouts, image cancellation, and download delegates differ. Encode directory/filename path components correctly and validate downloaded relative paths; do not use a generic shared session solely to reduce lines.

Image requests carry a library/session generation plus photo key and requested rendition. Start with at most two simultaneous image requests, prioritizing the active preview, coalescing identical requests, and cancelling queued/in-flight work when no consumer needs it. Use a memory cache with a 64 MiB decoded-image cost limit; downsample thumbnails for their display size. Do not persist camera images on disk in this change. Treat these bounds as tunable defaults, tested with injected configuration.

Cancel obsolete work when previews change, tiles leave demand, or the library disconnects/replaces. A late response from an old camera/session must never populate a new library, even if a filename matches. Failed thumbnails use an accessible placeholder and do not disconnect an otherwise healthy library. Retry on renewed demand or explicit user action without a tight retry loop.

During the web migration, fix `CameraSchemeHandler` to retain/cancel its URLSession tasks and suppress callbacks after WebKit stops them. Replace camera-supplied `innerHTML` labels with text nodes and encode path components in the remaining web adapter. These are interim safeguards, removed with the web code at final cutover; their final contracts are covered by native image/text tests.

Alternative: rely on `AsyncImage` alone. It does not define the shared camera-specific admission, request priority, decoded-memory budget, and session-generation policy this app needs.

### 7. Ordinary compilation and behavior-focused tests

Introduce one build helper/source manifest used by `Makefile`, `build.sh`, and the test runner for core/UI sources, target, framework list, and module-cache configuration. Keep their distinct entry points and packaging/signing responsibilities. Tests get an explicit `tests/main.swift` driver and callable suites/helpers; no splitting app text at a marker or concatenating application source into test source. No package-manager migration is necessary.

Preserve service fixture tests for HTTP failures, progress, archives, collisions, snapshots, credentials, stale generations, cancellation/draining, and sleep. Replace DOM assertions with native model tests and focused AppKit/SwiftUI host integration checks. Check stable image request counts and generation handling rather than inspecting SwiftUI's internal view recreation. Exercise actual responder events, accessibility, modal updates, narrow layouts, and previews in a host window; document manual checks where programmatic inspection cannot establish correctness.

## Risks / Trade-offs

- [UI migration regresses selection or keyboard focus] → Capture the accepted baseline first, retain stable keys, and port interaction scenarios before removing the web gallery.
- [Radio state is accidentally simplified away] → Keep operation generations, revision checks, serialized native calls, and drain locks; require existing race/cancellation suites at each service checkpoint.
- [SwiftUI lacks a required interaction] → Use a small AppKit-backed view or responder adapter behind the same presentation model, without restoring WebKit.
- [Native image loading overwhelms slow camera Wi-Fi or memory] → Bound concurrency and decoded cache cost, prioritize preview, cancel stale demand, and test the limits with a local fixture.
- [Settings modal stops asynchronous progress] → Retain the AppKit lifecycle and verify an actual export can finish with Settings open and its child sheet behavior intact.
- [Other active changes overlap migration files] → Inspect their implementation status at start/integration; preserve delivered behavior and leave unimplemented feature scope independent.
- [More files or initial migration code increase line count] → Judge success by removed bridge/state duplication and clear responsibilities rather than a promised line-count reduction.

## Migration Plan

1. Record working-tree state and accepted interactions; run baseline tests/builds and note hardware limitations. Preserve unrelated edits and active change artifacts.
2. Extract services and test sources, centralize build inputs, introduce typed boundaries behind temporary WebKit adapters, and keep the current UI working.
3. Add native Settings, verify parity, then remove the settings HTML and settings bridge. Keep the existing browser temporarily.
4. Add the image pipeline and native browser/preview/progress using the extracted services. Verify parity at the minimum window sizes and with large fixture libraries.
5. Remove the remaining embedded HTML, WebKit adapters/scheme handler, WebKit linkage, and obsolete DOM tests. Update documentation and record validation evidence.

Each phase is a reviewable checkpoint. If a phase fails parity, revert that phase while retaining the previous functional UI and unchanged preference formats. No destructive data migration or permanent runtime UI selector is introduced. Do not remove the old presentation until its replacement passes the corresponding checks.

## Open Questions

No product decision blocks implementation. Confirm the Finder-style selection change's delivery status at the baseline checkpoint. Measure image concurrency/cache defaults on the intended camera when hardware is available; keep physical checks outstanding and Bluetooth support experimental until evidence is recorded.
