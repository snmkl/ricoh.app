## ADDED Requirements

### Requirement: Shared download activity indicator

The app SHALL display a shared progress indicator immediately after accepting either a single-photo or selected-photo download. The indicator MUST remain visible independently of selection state and above the photo preview until the operation ends. It SHALL identify the current stage, current filename during transfer, and completed/total file counts. Its stage text MUST be accessible to assistive technology.

#### Scenario: Download a photo from the preview
- **WHEN** the user clicks FULL RES for a photo
- **THEN** the app displays download activity above the preview with that photo's filename and a total of one file

#### Scenario: Browse while a batch downloads
- **WHEN** the user starts a batch download and changes the selection or opens or closes the preview
- **THEN** the active indicator remains visible and continues reporting the original operation's files and progress

### Requirement: Measured transfer progress

The app SHALL update progress during each active file transfer. If the current transfer supplies a positive usable expected byte count, the app SHALL show its measured progress and a transfer percentage calculated by equally weighting the requested files: `(completedFiles + activeFileFraction) / totalFiles`. The active-file fraction MUST remain between zero and one. The completed-file count SHALL increase only after a successful HTTP response and successful staging of the file.

#### Scenario: Known-length single photo
- **WHEN** part of a photo with a usable expected length has been received
- **THEN** the indicator advances before the photo finishes and displays the corresponding transfer percentage

#### Scenario: Batch moves to its next photo
- **WHEN** the first of three requested photos is successfully transferred and staged
- **THEN** the indicator reports one of three files completed and identifies the next photo as it begins transferring

### Requirement: Unknown-length transfers remain observable

When the camera supplies no usable expected byte count, the app SHALL show an indeterminate indicator with the filename and completed/total file counts. It MUST NOT display an estimated numeric percentage as measured progress for that active transfer.

#### Scenario: Camera omits content length
- **WHEN** a photo is transferring without a usable expected byte count
- **THEN** the app shows ongoing activity and file counts without a numeric transfer percentage until a usable length becomes available or the transfer finishes

### Requirement: Explicit post-transfer stages and save outcome

The app SHALL distinguish transfer from ZIP creation, waiting for a save location, and saving. ZIP creation and stages without measurable progress SHALL use indeterminate feedback. The app SHALL preserve a direct image save for a single photo and ZIP output for multiple photos. It MUST report success only after the selected destination has been written successfully.

#### Scenario: Batch transfer completes
- **WHEN** every requested photo has been successfully transferred and staged
- **THEN** the app switches to a ZIP creation stage without reporting that the download has been saved

#### Scenario: Save dialog is open
- **WHEN** the app requests a destination using the native save dialog
- **THEN** its operation remains active and the indicator identifies that it is waiting for a save location

#### Scenario: Destination write succeeds
- **WHEN** the resulting photo or ZIP is successfully written to the selected destination
- **THEN** the app reports success, clears the active indicator, releases temporary resources, and restores eligible download actions

#### Scenario: User dismisses the save dialog
- **WHEN** the user cancels the native save dialog
- **THEN** the app reports cancellation, clears the indicator, releases temporary resources, restores eligible download actions, and does not report success

### Requirement: One active download operation

The app SHALL permit only one active download operation, including its archive and save stages. All download actions MUST be disabled while it is active, and the native handler MUST reject additional requests without starting another operation. Progress events for a completed or different operation MUST NOT alter the active operation's UI.

#### Scenario: Duplicate download request
- **WHEN** another download request reaches the native handler during an active operation
- **THEN** no second transfer, archive, or save dialog starts and the active operation continues normally

#### Scenario: Selection changes during download
- **WHEN** the selection changes while an operation is active
- **THEN** download actions remain disabled until the operation ends

#### Scenario: Late event arrives
- **WHEN** a delayed progress event from an earlier operation arrives after a new operation has started
- **THEN** the app ignores it and preserves the new operation's indicator and controls

### Requirement: Explicit failure and recovery

The app SHALL treat transport errors, non-success HTTP responses, staging errors, archive failures, and destination-write errors as failed operations. It MUST report a useful failure message, clear active progress, release temporary resources, and restore eligible download actions. A failed batch MUST NOT be presented as a successfully saved partial ZIP.

#### Scenario: A photo fails during a batch
- **WHEN** any requested photo encounters a transport error, unsuccessful HTTP response, or staging error
- **THEN** the app stops the batch, identifies the failure, cleans up staged data, and offers no partial ZIP as a successful result

#### Scenario: ZIP creation fails
- **WHEN** the archive process cannot start, exits unsuccessfully, or produces no valid output
- **THEN** the app reports archive failure and ends the operation without presenting a success message

#### Scenario: Destination cannot be written
- **WHEN** saving the completed photo or ZIP to the chosen destination fails
- **THEN** the app reports save failure and resets the download state

#### Scenario: Start again after an error
- **WHEN** a failed operation has been cleaned up and the user starts another eligible download
- **THEN** the new operation begins with fresh counts and no stale progress or locked controls
