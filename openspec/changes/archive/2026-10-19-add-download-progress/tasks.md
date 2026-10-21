## 1. Define the download lifecycle and bridge

- [x] 1.1 Add operation state in `DownloadHandler` for a unique ID, immutable file list, completed count, current file, phase, and unique temporary directory; reject overlapping operations.
- [x] 1.2 Add structured, JSON-serialized native-to-JavaScript events for progress, phase changes, and terminal outcomes; dispatch WebKit updates on the main queue and ignore stale operation IDs.

## 2. Report real transfer progress

- [x] 2.1 Replace blocking photo reads with sequential `URLSessionDownloadDelegate` transfers, move completed temporary downloads into operation staging, and validate HTTP success and staging writes before counting a file as completed.
- [x] 2.2 Report current filename, completed/total file counts, and equal-file-weighted transfer percentage for usable expected lengths; emit indeterminate progress for unknown lengths and throttle byte updates while keeping phase/file-boundary events immediate.
- [x] 2.3 Stop on transfer or staging failure and route all errors through one cleanup path that releases operation state and temporary files.

## 3. Cover archive and save stages

- [x] 3.1 Preserve direct single-photo output and batch ZIP output; create the ZIP inside operation-owned temporary storage, emit archive activity, and check process startup, exit status, and usable output.
- [x] 3.2 Emit waiting-for-destination and saving stages around `NSSavePanel` and the destination write; finish successfully only after the file is saved, and handle dismissal and write failure through terminal cleanup.

## 4. Add the shared progress interface

- [x] 4.1 Add a responsive status panel with filename, stage, counts, an accessible progress element, and polite stage announcements; keep it visible above the preview and clear of selection controls at the minimum window size.
- [x] 4.2 Route both download entry points through a shared start function, disable every download action immediately, and ensure selection and preview updates cannot re-enable them during an active operation.
- [x] 4.3 Render determinate and indeterminate events, distinguish transfer completion from saving, and reset the panel and eligible controls on success, failure, or save-dialog dismissal while reporting the terminal outcome.

## 5. Validate and document

- [x] 5.1 Exercise native progress with a controllable HTTP fixture: a slow known-length photo, an unknown-length response, a multi-photo batch, a transport interruption, and a non-success HTTP response; verify counts, phases, failure cleanup, and restart after failure.
- [x] 5.2 Verify archive launch/exit/output failure, staging-write failure, save dismissal, and destination-write failure through targeted failure injection; confirm no incomplete batch is reported as saved and temporary storage is released.
- [x] 5.3 Check progress calculation, operation-ID filtering, duplicate native requests, JSON payloads containing quotes, and control state when selection changes during download.
- [x] 5.4 Build using `./build.sh` and smoke-test the resulting app: single-photo preview, batch ZIP contents, progress visibility while browsing, minimum-size layout, accessibility, and save outcomes. Run a Ricoh camera smoke test when hardware is available and record any validation limits.
- [x] 5.5 Update `README.md` with the progress stages, unknown-length behavior, one-operation limit, and explicit batch failure behavior.
