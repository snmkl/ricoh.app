## Automated validation

- `python3 tests/run-tests.py` passed on macOS, including a rerun after strengthening native request admission during saving.
- The harness compiles the actual app source and uses a localhost HTTP camera fixture. It verifies intermediate known-length progress, unknown-length activity, batch file counts and percentage weighting, HTTP errors, interrupted transfers, retry after failure, and JSON filenames containing quotes and backslashes.
- Native failure injection covers staging writes, archive launch, nonzero archive exit, missing or invalid ZIP output, save dismissal, and destination-write failure. Terminal paths release temporary files, and failed batches do not offer partial ZIPs.
- Requests sent at every active stage and at save selection are rejected. Single-photo output bytes and the expected batch ZIP entries are checked.
- The embedded HTML runs in WKWebView for preview and selection download actions. Assertions cover initial feedback, control locking during browsing and selection changes, stale events, measured and indeterminate rendering, archive status, terminal reset, fresh counts, accessibility attributes, and panel bounds/stacking at 480 × 360.
- `./build.sh` passed, producing `build/GRBrowser.app`; bundle signature verification passed. Launching the packaged app through Launch Services succeeded and its process was verified running.
- `openspec validate add-download-progress --strict` and `git diff --check` passed.

## Validation limits

A physical Ricoh camera was not exercised in this session; firmware-specific response lengths and real camera Wi-Fi performance remain hardware smoke checks. Native save-dialog outcomes are injected in the harness, so actual save-panel interaction and screen-reader announcements were not manually exercised. Layout checks inspect WebKit geometry and accessibility markup rather than a visual screenshot or screen-reader session.

The updated bundle is available in the repository's build directory. To update the installed app after review, quit it and run `./build.sh --install`.
