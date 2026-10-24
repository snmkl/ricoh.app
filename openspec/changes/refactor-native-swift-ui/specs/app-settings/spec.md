## MODIFIED Requirements

### Requirement: Native Settings modal

The app SHALL provide a native macOS modal Settings window opened from a visible settings control and Command-comma. Its form SHALL use native SwiftUI/AppKit controls rather than a web view. It SHALL expose a standard title-bar close button, the selected download folder, Separate files and ZIP archive batch format choices, and the known camera network list with a Forget action for every entry. Existing Bluetooth discovery/setup and remembered-camera controls SHALL remain available separately from Wi-Fi network history. The window MUST support keyboard navigation, accessible labels, and dismissal by its close button, Command-W, or Escape, without requiring an additional form Close control. Closing Settings MUST leave the browser open and active downloads running. Preference and download updates MUST continue while the modal is open. Repeated opening MUST NOT create overlapping Settings modals. Native form layout and scrollable device lists MUST remain usable within the available screen and the supported 400 by 360 point minimum size without JavaScript measurement.

#### Scenario: Open and close settings
- **WHEN** the user activates the settings control or Command-comma
- **THEN** the same native Settings window opens with current values and can be closed with its standard close button, Command-W, or Escape without closing the browser

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

#### Scenario: Manage Bluetooth history separately
- **WHEN** Settings displays remembered Bluetooth cameras and Wi-Fi networks
- **THEN** native controls preserve their existing independent Forget behavior, active-device restrictions, and setup/discovery guidance

#### Scenario: Use Settings with long lists or a small screen
- **WHEN** many devices are remembered or the Settings window is reduced to its supported minimum
- **THEN** its controls remain keyboard accessible and device lists scroll without positioning the window outside the available screen
