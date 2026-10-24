# Implementation validation

Date: 2026-10-23

## Automated results

- `python3 tests/run-tests.py`: PASS (complete suite).
- `make build`: PASS.
- `./build.sh`: PASS, including plist validation and strict ad-hoc signature verification.
- `openspec validate add-finder-style-image-selection --strict`: PASS.
- `git diff --check`: PASS.

The callable selection suites in `tests/SelectionTests.swift` are registered in
`tests/main.swift`. The native suite uses actual AppKit host-window mouse/key
routing, native accessibility press actions, and the existing camera, image and
export fixtures. It covers:

- Command clicks over thumbnail, filename, padding and checkbox in grid and list;
  combined Command-Shift precedence; ordinary preview and checkbox clicks;
  accessible labels, selected state, active state, and repeated keyboard checkbox
  activation.
- Forward/backward ranges, cross-directory duplicate basenames, fixed anchors,
  independent baseline selections, contraction, anchor crossing, repeated keys,
  Shift release/repress, direct item focus, and preview return.
- Shared column counts at multiple widths, grid/list changes, incomplete last
  rows, library boundaries, and scrolling/focusing a previously offscreen lazy
  endpoint through repeated native events.
- Additional-modifier, editable/control, preview, modal and sheet exclusions, plus
  the production Command-comma Settings shortcut.
- Stable loaded-image request counts and image generation, ordered selected keys
  and accessible counts, captured ZIP contents/progress/admission during selection
  changes, empty libraries, and disconnect/reconnect resets.

The existing browser, image, download, preferences, Settings, connection, camera
API and Bluetooth suites also pass. SwiftUI compilation and native fixture tests
required execution outside the restricted shell sandbox because Swift's macro
plugin cannot start its own sandbox inside that sandbox.

## Manual verification (task 5.3)

The user confirmed completion of physical-input validation in the native app.
The following checklist is complete based on that confirmation:

- [x] Command-click thumbnail, filename, padding and checkbox in each view; verify
  exactly one toggle, no preview, and retained independent selections. Check
  Command-Shift clicks use the inclusive range.
- [x] Hold Shift+Arrow for key repeat, reverse through the anchor, release and
  repress Shift, and verify contraction preserves independent baseline photos.
- [x] Open preview with an ordinary click, navigate it, dismiss it, and verify the
  displayed photo receives gallery focus and anchors the next Shift gesture.
- [x] Switch grid/list during a range and return gallery focus; verify membership,
  anchor and baseline survive. Resize across column-count thresholds and verify
  vertical movement follows the rendered rows, including an incomplete final row.
- [x] Extend beyond the visible lazy viewport; verify the endpoint scrolls into
  view and its white active outline remains distinct from blue selection.
- [x] Move focus to other controls, Settings and a sheet; verify gallery handling
  does not steal focus or consume their arrows.

Automated checks and user-confirmed manual validation are complete. This change
has not been archived.
