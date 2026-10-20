## Context

`GRBrowser.swift` contains both the embedded WebKit interface and the native `DownloadHandler`. `dlSelected()` writes static text inside the selection bar; `dlCurrent()` has no progress UI. Native downloads use blocking `Data(contentsOf:)`, and the batch loop prints completed counts only to the terminal. Selecting fewer photos or opening the preview can hide the existing text. `_dlDone` is the only native-to-JavaScript lifecycle callback.

Batch downloads currently skip failed transfers and suppress staging and archive errors. That makes a progress indicator potentially misleading: a ZIP can be offered even when the requested files were not all fetched. This change needs an explicit lifecycle across the transfer, archive, save, and error paths.

The implementation must retain the single Swift source, macOS 13.3 compatibility, existing camera endpoints, native save dialog, and dependency-free app build.

## Goals / Non-Goals

**Goals:**

- Show live, accessible progress for both download entry points throughout the operation.
- Distinguish measured transfer progress from activity with no measurable total.
- Preserve direct single-file output and batch ZIP output.
- Keep progress associated with one active operation and finish every path cleanly.
- Make transfer or packaging failure visible instead of producing a silently incomplete result.

**Non-Goals:**

- Transfer cancellation, pause/resume, automatic retries, background persistence, or a download history.
- Parallel downloads, speed estimates, remaining-time estimates, or a byte-weighted total requiring advance requests for every photo's size.
- Changes to browsing, thumbnails, camera discovery, or the app packaging workflow.

## Decisions

### 1. Use a shared status panel outside selection and preview state

Add one download status area outside the selection bar and lightbox containers. Position it above the preview overlay, with room for the selection bar at the minimum window size. Both download actions enter the same JavaScript start path. Show phase text, the current filename, completed/total file counts, and an HTML progress element. Use an accessible label and a polite status region; update the visual value without announcing every byte event.

The panel remains visible if selection changes, the lightbox closes, or the user navigates between photos. Reusing only the existing selection-bar span would leave single-photo downloads and hidden selections without feedback.

### 2. Receive transfer progress through URLSession download delegates

Replace `Data(contentsOf:)` in `DownloadHandler` with a dedicated `URLSession` using `URLSessionDownloadDelegate`. Receive byte updates through `didWriteData`, validate successful HTTP responses, and move each completed temporary download into an operation-owned staging directory before its delegate callback returns. Keep transfers sequential to match the existing camera workload.

For a positive expected byte count, calculate the active file's fraction and show an overall **transfer** percentage as `(completedFiles + activeFileFraction) / totalFiles`. This equally weights files, is explicitly transfer progress, and does not claim to measure all batch bytes. For an absent or unusable expected length, show indeterminate activity and completed-file counts without a fabricated percentage. Recompute from current observations if usable length becomes available.

A completion-only callback or timer animation cannot report actual movement during a large photo transfer. Download tasks also avoid keeping every fetched photo in memory solely to measure progress.

### 3. Send structured lifecycle events through the existing bridge

Represent an operation with an identifier, immutable file list, current index, completed count, staging directory, and phase. Native events carry the operation ID, phase, filename, counts, optional transfer fraction, and optional terminal message. Serialize payloads with `JSONSerialization` before calling a JavaScript callback on the main queue; do not interpolate filenames or error strings into quoted JavaScript.

Use phases `preparing`, `downloading`, `archiving`, `awaiting-save`, `saving`, `completed`, `failed`, and `cancelled` (save-dialog dismissal). Emit transfer updates at most about ten times per second, with immediate phase and file-boundary updates. Ignore events for an inactive operation. This prevents stale callbacks from resetting a later download and avoids flooding WebKit with byte events.

### 4. Own the entire operation until the save outcome

Disable every download action immediately on start, and have the native handler reject a second operation while one is active. Keep the guard active through archive creation and the native save panel. Derive button availability from active-operation state plus the current selection/preview state so selection updates cannot re-enable downloads prematurely.

Run transfer and archive work off the main thread. Show `Creating ZIP…` and `Waiting for save location…` as indeterminate stages; transfer reaching 100% is not a successful save. Only a successful destination write emits `completed`. Show the existing style of completion toast and hide/reset the active indicator on every terminal outcome.

Stopping the batch on its first transfer or staging failure keeps the result honest without introducing partial-download recovery UI. Check archive launch, exit status, and output, and report save failures. Centralize terminal cleanup so the operation guard is released and temporary files removed after success, error, or save-dialog dismissal. Keep archive output inside the unique operation directory rather than using a shared date-based temporary ZIP path.

## Risks / Trade-offs

- Camera responses may omit content length → use indeterminate progress with real completed counts and filenames.
- Equal weighting means differently sized photos advance at different rates → label the percentage as transfer progress and retain file counts; avoid claiming byte-weighted batch progress or an ETA.
- Delegate callbacks and WebKit updates run on different queues → serialize native operation changes and dispatch all UI callbacks and save-panel work to the main queue.
- A ZIP or destination write can fail after transfer reaches 100% → show explicit archive/save stages and emit success only after writing finishes.
- Existing batch behavior allowed partial results → fail explicitly and discard staging files; the user can adjust the selection and retry.
- Hardware availability can limit validation → use a controllable local HTTP fixture for known/unknown lengths and failures, then perform a camera smoke test when available.

## Migration Plan

No persistent data or settings require migration. Build with `./build.sh` and inspect the resulting app. After review, the user can quit the installed app and run `./build.sh --install` to update it. Rollback consists of reverting the download UI/handler change and rebuilding the app.

## Open Questions

None blocking artifact completion. Confirm actual camera content-length behavior during hardware validation; the unknown-length path is required regardless.
