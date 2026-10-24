## ADDED Requirements

### Requirement: Native browser presentation

The app SHALL render its main connection controls, photo grid/list, selection actions, preview, status, and download progress using native SwiftUI/AppKit presentation on macOS 13.3 or later. The completed migration MUST NOT require WebKit, embedded HTML/CSS/JavaScript, script messages, or a custom web URL scheme. The app SHALL retain its existing application identity and readable preference/history formats without requiring the user to reconfigure the app.

#### Scenario: Open the native browser
- **WHEN** the user launches the app after migration
- **THEN** a native browser window presents connection controls and the appropriate empty or library state without loading a web view
- **AND** existing folder, export-format, network-history, and Bluetooth-history records remain available

#### Scenario: Use the minimum window size
- **WHEN** the main window is resized to its supported 480 by 360 point minimum
- **THEN** the connection target, adjacent Find cameras action, primary connection action, and Settings remain usable in one header line
- **AND** truncated target names retain their full accessible label or help text

### Requirement: Authoritative typed operation state

Connections and downloads SHALL each have one native lifecycle owner exposing typed state/events tagged with operation or session identity. Native views SHALL derive their primary action, enabled actions, and progress from these owners rather than maintaining parallel operation lifecycles. Services MUST enforce admission independently of view controls. Connection setup and download operations MUST remain mutually exclusive through destination selection, transfer, save, and non-cancellable connection cleanup. Events from superseded operations MUST NOT alter current presentation or persisted history.

#### Scenario: Cancel while native association drains
- **WHEN** the user cancels a connection while a native association is still in flight
- **THEN** the UI displays cancellation/draining state and rejects conflicting connection and download actions until cleanup completes
- **AND** a late successful association does not publish photos or revive the cancelled operation

#### Scenario: Receive an old download result
- **WHEN** a completed operation's delayed event arrives during a subsequent download
- **THEN** the current operation retains its progress, captured inputs, and action availability

#### Scenario: Request another download during folder selection
- **WHEN** an accepted download is waiting for the user to choose its destination and another request is submitted
- **THEN** no second picker or operation starts, even if the request bypasses the visible controls

### Requirement: Connection workflow parity

The native browser SHALL preserve Current Wi-Fi, available remembered network, and remembered/observed Bluetooth target routes; explicit target selection; device-name disambiguation; connect/cancel/drain/disconnect actions; truthful transport versus verified-library status; and explicit manual recovery. Discovery or target selection MUST NOT wake, join, or connect to a camera. A verified library SHALL continue to require the existing HTTP and route-specific identity checks. BLE release MUST remain distinct from Wi-Fi library loss. The app MUST NOT introduce background waking, silent target substitution, or network restoration as part of this migration.

#### Scenario: Select a target without connecting
- **WHEN** the user chooses a Bluetooth or Wi-Fi target in the native picker
- **THEN** only the intended target changes and no camera write, network association, or library verification starts

#### Scenario: Release Bluetooth after handoff
- **WHEN** a Bluetooth route completes verification and releases its setup link
- **THEN** the browser keeps the verified Wi-Fi library available and displays the released Bluetooth state independently

#### Scenario: Recover from rejected automatic setup
- **WHEN** automatic Bluetooth setup is rejected
- **THEN** the browser provides the existing stage-specific error and explicit manual Wi-Fi recovery without automatically switching routes

### Requirement: Stable gallery and selection identity

Photos SHALL be identified by exact camera directory and filename, with explicit display order. Selection, active-photo identity, and preview state MUST remain independent of thumbnail request completion. A selection-only change MUST NOT clear the image cache, restart unchanged loaded-image requests, or replace the library. Grid/list switching SHALL retain valid selection and active identity; disconnect or library replacement SHALL clear prior library-specific state. Plain-click preview, unmodified checkbox toggles, bulk selection, selected counts, and displayed-order batch requests SHALL retain the accepted pre-migration behavior.

If Finder-style modifier/range selection has been delivered before native migration, the app MUST also retain its anchor, baseline, modifier precedence, keyboard destinations, focus, and reset semantics. This change MUST NOT introduce the separately proposed gestures when they have not been delivered.

#### Scenario: Select among already loaded photos
- **WHEN** the user toggles selection repeatedly after visible thumbnails have loaded
- **THEN** counts and action availability update without new requests for those unchanged cached thumbnails

#### Scenario: Duplicate basenames in different directories
- **WHEN** two displayed photos share a filename but have different directories
- **THEN** they have separate selection, preview, and image-cache identities and produce distinct download keys

#### Scenario: Switch view during selection
- **WHEN** the user changes between grid and list with a nonempty selection
- **THEN** the same valid photo keys remain selected and any valid active photo is retained

#### Scenario: Replace the library
- **WHEN** a connection attempt clears the library, the session disconnects, or another library is installed
- **THEN** old selection, preview, active-photo, and any range-session state cannot affect the replacement library

### Requirement: Bounded cancellable image loading

Thumbnail and preview loading SHALL share an explicitly bounded request scheduler, coalesce identical requests, prioritize the active preview, and use a decoded-memory cache with a defined cost limit. Default limits SHALL be two concurrent image requests and 64 MiB of decoded cache cost; tests SHALL be able to inject smaller limits. Request identity SHALL include the library generation, photo key, and rendition. Queued or active requests SHALL be cancelled when no longer demanded or when the library is invalidated. Callbacks from invalidated requests MUST NOT update current image state. Thumbnail failures SHALL expose a usable placeholder without invalidating a verified camera session or causing unbounded automatic retries.

#### Scenario: Browse a large library
- **WHEN** the user scrolls quickly through more photos than the cache can hold
- **THEN** image request concurrency and retained decoded cache cost remain within configured limits and obsolete demand is cancelled

#### Scenario: Open a preview while thumbnails are queued
- **WHEN** a preview is requested while thumbnail work is pending
- **THEN** the preview receives priority without exceeding the shared concurrency limit

#### Scenario: Old image response arrives after reconnect
- **WHEN** an image from a previous library completes after another session installs a matching filename
- **THEN** the old response is discarded rather than displayed or cached under the new session

#### Scenario: A thumbnail cannot load
- **WHEN** an image request fails or returns invalid image data
- **THEN** the photo remains identifiable and selectable with an accessible failure placeholder, and the verified library remains usable

### Requirement: Safe camera text and URL construction

Camera-supplied names and errors SHALL render as text without interpretation as markup or executable content. Camera endpoint construction SHALL preserve supported directory/filename characters through correct path-component encoding, retain existing response validation, and reject invalid relative download paths. HTTP configuration SHALL remain appropriate to verification, image loading, or original-file transfer rather than weakening their distinct timeout and lifecycle policies.

#### Scenario: Render names containing punctuation
- **WHEN** a camera returns a name containing quotes, angle brackets, spaces, or URL-significant characters
- **THEN** the name displays literally and any supported photo path addresses the intended camera resource without creating markup or query parameters from the name

#### Scenario: Invalid download path
- **WHEN** a download request includes an absolute path, an empty path component, or dot traversal
- **THEN** it fails before transfer/publication and cannot write outside its staging/destination policy

### Requirement: Native preview and download feedback

The native preview SHALL retain previous/next navigation, filename and position information, Escape dismissal, and original-file download. Closing preview SHALL restore usable gallery focus. A shared accessible download indicator SHALL remain visible above the preview and independent of current selection, preserving existing measured/indeterminate progress, stage labels, captured-operation inputs, and terminal success/failure/cancellation behavior. Keyboard handling MUST remain scoped to the appropriate view and MUST NOT consume unrelated controls' input.

#### Scenario: Browse during download
- **WHEN** a batch is active and the user changes selection, switches view, or opens/navigates/closes preview
- **THEN** progress remains visible for the original batch, its file snapshot remains unchanged, and additional downloads remain unavailable

#### Scenario: Navigate and dismiss preview
- **WHEN** the preview owns input and the user presses Left, Right, or Escape
- **THEN** the corresponding existing preview action occurs without unintended gallery selection changes, and dismissal restores gallery focus

#### Scenario: Another control owns focus
- **WHEN** a native selector, editable field, Settings modal, or child sheet owns keyboard focus
- **THEN** gallery or preview handlers do not intercept that control's arrow keys or dismiss it as a gallery action
