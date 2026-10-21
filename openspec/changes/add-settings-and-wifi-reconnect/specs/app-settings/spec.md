## ADDED Requirements

### Requirement: Native Settings modal

The app SHALL provide a native macOS modal Settings window opened from a visible settings control and Command-comma. It SHALL expose a standard title-bar close button, the selected download folder, Separate files and ZIP archive batch format choices, and the known camera network list with a Forget action for every entry. The window MUST support keyboard navigation, accessible labels, and dismissal by its close button, Command-W, Escape, or the form's Close control. Closing Settings MUST leave the browser open and active downloads running. Preference and download updates MUST continue while the modal is open. Repeated opening MUST NOT create overlapping Settings modals.

#### Scenario: Open and close settings
- **WHEN** the user activates the settings control or Command-comma
- **THEN** the same native Settings window opens with current values and can be closed with its standard close button, Command-W, Escape, or Close control without closing the browser

#### Scenario: Reopen Settings
- **WHEN** the user closes and reopens Settings
- **THEN** the native window displays the latest saved values without opening a duplicate modal or resetting preferences

#### Scenario: Download completes while Settings is open
- **WHEN** an active download finishes while Settings is modal
- **THEN** native saving and browser progress updates complete normally without requiring Settings to close

#### Scenario: Folder picker belongs to Settings
- **WHEN** the user chooses a folder from Settings
- **THEN** the native directory picker attaches to the Settings window and its parent cannot close while that child sheet is attached

#### Scenario: Inspect remembered networks
- **WHEN** Settings opens with saved camera networks
- **THEN** each network is listed with its name, last successful connection, and Forget action, including networks that are currently unavailable

### Requirement: Persistent preferences

The app SHALL persist its chosen folder and batch format across launches and rebuilds using its existing app identity. On first use it SHALL have no selected folder, ZIP archive as the batch default, and no known networks. Invalid stored values MUST fall back to valid defaults without preventing startup.

#### Scenario: Preferences survive restart
- **WHEN** the user selects a folder and Separate files, closes the app, and reopens it
- **THEN** Settings shows that folder and format, and subsequent downloads use them

#### Scenario: First launch or invalid preferences
- **WHEN** preferences are absent or a persisted field is invalid
- **THEN** the app uses the documented defaults for absent or invalid fields and remains usable

### Requirement: Choose and validate a direct destination

The app SHALL use a native directory picker to choose the download folder. It SHALL validate the selected folder before starting camera transfers. If no usable folder is configured, it MUST request a usable folder first; cancelling MUST start no transfer and leave existing preferences unchanged. Once a usable folder is configured, downloads SHALL save directly there without a per-download save dialog.

#### Scenario: Choose a folder in settings
- **WHEN** the user chooses an available writable directory in Settings
- **THEN** the app persists and displays it as the destination for subsequent downloads

#### Scenario: Download to the configured folder
- **WHEN** a download begins with a usable configured directory
- **THEN** the app transfers and saves into that directory without opening a save dialog

#### Scenario: Missing or unavailable destination
- **WHEN** a download is requested with no configured folder or an unavailable or unwritable folder
- **THEN** the app requests a replacement directory before transferring any photo and stores a successfully chosen usable replacement

#### Scenario: Cancel folder selection
- **WHEN** the user dismisses the required directory picker
- **THEN** the operation ends as cancelled, performs no transfer, and preserves the previous folder preference

### Requirement: Select batch export format

The app SHALL allow Separate files or ZIP archive as the default for downloads containing multiple photos. Separate files SHALL save each photo in its original format into the selected directory; ZIP archive SHALL save one archive containing all requested photos. Single-photo downloads SHALL save the original image regardless of the batch preference. Both batch modes SHALL preserve sequential camera transfers.

#### Scenario: Save separate photos
- **WHEN** the user downloads multiple photos with Separate files selected
- **THEN** the destination receives each original photo as an individual file and no ZIP is created

#### Scenario: Save a ZIP
- **WHEN** the user downloads multiple photos with ZIP archive selected
- **THEN** the destination receives one ZIP containing all requested photos

#### Scenario: Download one preview photo
- **WHEN** the user downloads one photo while ZIP archive is the batch preference
- **THEN** the app saves the original image file rather than wrapping it in a ZIP

### Requirement: Preserve existing destination files

The app MUST NOT overwrite existing destination files. It SHALL use the original basename where available and add a numeric suffix before the extension to resolve collisions, including duplicate basenames within a selection. ZIP filenames SHALL follow the same non-overwrite rule. Name reservation and publishing MUST remain safe if another process creates the proposed filename concurrently.

#### Scenario: Photo name already exists
- **WHEN** the destination already contains a photo with the requested basename
- **THEN** the new photo is saved under an available suffixed name and the existing file remains unchanged

#### Scenario: Duplicate basenames in one batch
- **WHEN** two camera directories contain selected photos with the same basename
- **THEN** both photos are saved under distinct filenames without losing either photo

#### Scenario: Destination name is created concurrently
- **WHEN** another process creates the proposed photo or ZIP filename before publication finishes
- **THEN** the app preserves that file and selects another available name or reports a save failure without overwriting it

### Requirement: Stable preferences for an active download

The app SHALL freeze the file list and export format when accepting a download and freeze its destination before starting transfers. Later preference changes MUST affect subsequent operations only. The existing one-operation guard SHALL remain active through destination selection, transfer, packaging, and saving.

#### Scenario: Change settings during transfer
- **WHEN** the user changes the folder or batch format while a download is transferring
- **THEN** the active operation completes using its captured destination and format, and the next download uses the updated preferences

#### Scenario: Duplicate request while choosing a folder
- **WHEN** another download is requested while the first operation is awaiting a directory choice
- **THEN** no second picker or transfer starts
