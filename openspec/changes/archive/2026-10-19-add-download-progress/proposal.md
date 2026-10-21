## Why

Downloads currently show only static text for a selection and no progress for a single photo opened in the preview. Camera Wi-Fi transfers can be slow, so users need visible feedback that the download is advancing and a clear distinction between transferring, creating a ZIP, and saving.

## What Changes

- Show a shared download progress indicator for single-photo and selected-photo downloads, including above the photo preview.
- Update the indicator during a file transfer with the current filename, completed/total file counts, and transfer percentage when the camera supplies a usable content length; show indeterminate activity otherwise.
- Show explicit preparation, transfer, ZIP creation, and save stages, and report success only after the destination file is written.
- Allow one download operation at a time, prevent duplicate download requests, and restore controls after success, failure, or save-dialog dismissal.
- Report transfer, archive, and save failures explicitly instead of silently saving an incomplete batch.

## Capabilities

### New Capabilities

- `download-progress`: Observable progress and lifecycle feedback for single-photo and batch downloads, with consistent completion and failure handling.

### Modified Capabilities

None; this repository has no existing OpenSpec capability specifications.

## Impact

- `GRBrowser.swift`: Embedded HTML/CSS/JavaScript, the download message bridge, and `DownloadHandler` transfer and save lifecycle.
- `README.md`: Describe the download indicator and its stages.
- Preserve direct single-photo saves and ZIP output for multiple photos, using the existing camera HTTP API and native save dialog.
- Use built-in WebKit, Foundation/URLSession, and `/usr/bin/ditto`; no additional dependencies or camera API changes.
- The standalone app must continue to build with `./build.sh`; installation remains a separate explicit script option.
