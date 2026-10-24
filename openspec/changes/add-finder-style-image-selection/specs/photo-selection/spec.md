## ADDED Requirements

### Requirement: Whole-card Command selection

The gallery SHALL support Command-click anywhere within a photo card to toggle that photo's membership in the selection without opening a preview or altering other selected photos. The thumbnail, overlay, background, and checkbox SHALL all participate in the same modifier-aware routing in grid and list views. Each click MUST produce exactly one action. Shift SHALL take precedence when Command and Shift are both held.

#### Scenario: Add a photo from its thumbnail
- **WHEN** the user Command-clicks an unselected photo's thumbnail while other photos are selected
- **THEN** that photo is added, existing selections remain, and no preview opens

#### Scenario: Remove a selected photo
- **WHEN** the user Command-clicks an already selected photo's overlay or card background
- **THEN** only that photo is removed and no preview opens

#### Scenario: Command-click the checkbox
- **WHEN** the user Command-clicks a photo's checkbox in either view
- **THEN** that photo toggles exactly once, other selections remain, and no preview opens

#### Scenario: Combined click modifiers
- **WHEN** the user Command-Shift-clicks a photo card
- **THEN** the app applies the Shift range-selection behavior once rather than toggling the endpoint

### Requirement: Anchored inclusive range selection

A plain card click, Command toggle, or unmodified checkbox toggle SHALL establish that photo as the next range anchor and end any previous range session. Direct keyboard focus on a different card SHALL establish a new origin without changing selection. Shift-click SHALL select the inclusive range between the anchor and clicked photo in displayed order, regardless of camera directory. With no valid origin, Shift-click SHALL select only the clicked photo in addition to existing selections and establish it as the anchor. These interactions MUST work in both gallery views without opening a preview for modified clicks.

At the first range adjustment, the app SHALL capture the existing selection as a baseline. Subsequent Shift-clicks and Shift+Arrow presses SHALL retain that baseline and the fixed anchor, replacing the active range with the inclusive interval to the new endpoint. Photos in the baseline MUST remain selected even when the interval shrinks. Releasing Shift alone MUST NOT end the range session.

#### Scenario: Select forward while preserving independent choices
- **WHEN** photo B is the anchor, photos B and H are selected in displayed order A through H, and the user Shift-clicks E
- **THEN** B, C, D, E, and H are selected, E is the active endpoint, and the preview remains closed

#### Scenario: Select backward across directories
- **WHEN** E is the anchor and the user Shift-clicks B, with a camera-directory boundary between B and E
- **THEN** every photo from B through E is selected in displayed order together with the baseline selection

#### Scenario: Repeated Shift-click adjusts the range
- **WHEN** a range session anchored at B has baseline B and H and endpoint E, and the user Shift-clicks D
- **THEN** B, C, D, and H remain selected, E is removed, and B remains the anchor

#### Scenario: Start without a previous interaction
- **WHEN** no valid active photo or anchor exists and the user Shift-clicks D
- **THEN** D is selected alongside any existing selections and becomes the anchor and active photo

#### Scenario: Shift-click the checkbox
- **WHEN** the user Shift-clicks an endpoint photo's checkbox with an existing anchor
- **THEN** the same inclusive range is selected as a Shift-click on its thumbnail, without an extra checkbox toggle

### Requirement: Keyboard range extension and contraction

While the gallery owns keyboard focus and the preview is closed, Shift+Arrow SHALL adjust the active range endpoint using the highlighted photo or remembered last-interacted photo as the origin of a new session. With no valid origin, the first Shift+Arrow SHALL highlight and select the first displayed photo only, preserving any baseline selection. The anchor SHALL stay fixed for the session, and reversal SHALL contract the active interval and then extend it on the other side of the anchor. Handled events MUST suppress default scroll movement and MUST NOT open a preview.

#### Scenario: Extend and shrink a range
- **WHEN** B and H were selected before a range session anchored at B, the user presses Shift+Right three times to reach E, then Shift+Left once
- **THEN** B, C, D, and H are selected, D is highlighted, and E is deselected

#### Scenario: Preserve baseline photos inside a contracted interval
- **WHEN** B, D, and H were selected before extending a range from B to E, and the user contracts its endpoint to C
- **THEN** B, C, D, and H remain selected because D belonged to the baseline

#### Scenario: Cross the anchor
- **WHEN** a session with baseline B and H is anchored at B with endpoint C, and the user presses Shift+Left twice
- **THEN** A, B, and H are selected and A is highlighted

#### Scenario: Use the last clicked photo after preview
- **WHEN** the user plain-clicks C, closes its preview, and presses Shift+Right with gallery focus restored
- **THEN** C and D are selected together with any baseline selection and the preview stays closed

#### Scenario: Start at a keyboard-highlighted photo
- **WHEN** the user directly focuses D and presses Shift+Left without an active range session
- **THEN** C and D are selected together with the baseline selection and D is the anchor

#### Scenario: Initialize keyboard range selection
- **WHEN** the nonempty gallery has keyboard focus but no valid remembered photo and the user presses Shift+Arrow
- **THEN** only the first photo is added to existing selections and becomes the highlighted anchor

#### Scenario: Resume after releasing Shift
- **WHEN** the user releases Shift after extending from B to D and later presses Shift+Left without another selection-origin action
- **THEN** the endpoint contracts to C using the original anchor and baseline

### Requirement: Layout-aware keyboard destinations

In grid view, Shift+Left/Right SHALL move one photo backward/forward in displayed order, including across row boundaries. Shift+Up/Down SHALL move one currently rendered row while preserving the column when that destination exists. Movement into an incomplete final row SHALL clamp to that row's last photo. Movement beyond the first or last row, or beyond the first or last photo horizontally, SHALL leave the endpoint unchanged. In list view, Shift+Left/Up SHALL move to the previous photo and Shift+Right/Down to the next. Selection SHALL always cover the inclusive linear interval in displayed order. Navigation MUST use the current layout after resize or view switching and MUST NOT wrap around the library.

#### Scenario: Navigate vertically in a three-column grid
- **WHEN** A through G appear in a three-column grid, B is the anchor, and the user presses Shift+Down
- **THEN** E is highlighted and B through E are selected together with the baseline

#### Scenario: Navigate into an incomplete last row
- **WHEN** A through G appear in a three-column grid, E is the anchor, and the user presses Shift+Down
- **THEN** G is highlighted and E through G are selected together with the baseline

#### Scenario: Stop at the library boundary
- **WHEN** G is the active endpoint in a library ordered A through G and the user presses Shift+Right or Shift+Down
- **THEN** the endpoint and selection remain unchanged

#### Scenario: Stop at the first row
- **WHEN** B is the active endpoint in the first row of a grid and the user presses Shift+Up
- **THEN** the endpoint and selection remain unchanged

#### Scenario: Switch to list navigation
- **WHEN** a range anchored at B with endpoint C is switched to list view and the user returns focus to C and presses Shift+Down
- **THEN** D becomes the endpoint, B remains the anchor, and the existing baseline is preserved

#### Scenario: Resize the grid
- **WHEN** the grid changes from three columns to two, B is the active origin, and the user presses Shift+Down
- **THEN** navigation uses the new two-column layout and targets D

### Requirement: Visible focus and scoped keyboard handling

The gallery SHALL be keyboard reachable and SHALL expose the active photo separately from selected membership through a visible highlight, keyboard focus, and accessible item selection state. Selection updates and view changes MUST retain the active photo's identity. A selection-only update MUST NOT invalidate the current image generation or restart unchanged loaded-thumbnail requests. A keyboard range move SHALL scroll its endpoint into view, including when the native lazy layout has not yet realized that item. Closing a preview SHALL return gallery focus to its displayed photo when present. Native preview and checkbox accessibility actions MUST remain usable alongside modifier-aware pointer routing.

Gallery range handling MUST NOT intercept events originating from unrelated controls, editable fields, an open preview, a native modal, or an attached sheet. Existing preview Left/Right/Escape and Command-comma Settings behavior SHALL remain available. Command, Option, or Control combined with Shift+Arrow SHALL NOT invoke gallery range handling.

#### Scenario: Retain focus through repeated selection updates
- **WHEN** the user repeatedly presses Shift+Arrow with the gallery focused
- **THEN** focus remains on the active endpoint, its highlight is distinguishable from selected membership, and unchanged loaded thumbnails generate no new image requests or library-generation changes

#### Scenario: Reveal an offscreen endpoint
- **WHEN** a Shift+Arrow move reaches a photo outside the visible gallery area
- **THEN** the photo scrolls into view, is realized by the lazy layout when necessary, and receives the active highlight and gallery focus

#### Scenario: Preserve accessible native actions
- **WHEN** the user activates a photo's preview or checkbox through native keyboard or accessibility actions without modifiers
- **THEN** the preview opens or that photo toggles exactly once according to the activated control, without requiring a pointer event

#### Scenario: Respect another control's arrows
- **WHEN** a toolbar selector or editable control owns focus and the user presses Shift+Arrow
- **THEN** gallery selection remains unchanged and gallery handling does not prevent the control's default behavior

#### Scenario: Respect Settings and attached sheets
- **WHEN** a native Settings modal or attached sheet is active and the user presses Shift+Arrow
- **THEN** gallery selection remains unchanged and its input handler does not claim first responder or consume the event

#### Scenario: Preserve preview navigation
- **WHEN** the preview is open and the user presses Left, Right, or Escape
- **THEN** the existing preview navigation or dismissal occurs without changing gallery selection

#### Scenario: Preserve Settings shortcut
- **WHEN** the user presses Command-comma from the gallery
- **THEN** the existing Settings window opens without changing gallery selection

### Requirement: Selection lifecycle and download compatibility

The app SHALL reset selection, active photo, range anchor, and baseline whenever the displayed library is cleared or replaced, including connection attempts and disconnects. Empty libraries and missing origins MUST NOT cause exceptions or select nonexistent photos. Grid/list switching SHALL preserve selection, anchor, endpoint, and baseline. Clear and Select all/Deselect all SHALL end the active range session and clear its anchor while retaining any valid active photo; the next range action SHALL use that active photo and the post-action selection as its baseline.

Plain card clicks SHALL continue to open previews, unmodified checkbox clicks SHALL toggle only their photo, and selection counts and download eligibility SHALL reflect every selection update. Batch requests SHALL use selected keys in displayed order. Selection changes during an active download MUST NOT change its captured files, enable another download, or disrupt progress reporting.

#### Scenario: Preserve existing click interactions
- **WHEN** the user clicks a card without modifiers and then closes the preview and clicks its checkbox without modifiers
- **THEN** the first click opens the preview without changing selection and the checkbox click toggles only that photo without reopening the preview

#### Scenario: Clear before a new range
- **WHEN** the active photo is C, the user clears selection, restores gallery focus, and presses Shift+Right
- **THEN** only C and D become selected using a new range session

#### Scenario: Bulk-select before a new range
- **WHEN** the active photo is C, the user selects all photos, restores gallery focus, and presses Shift+Right followed by Shift+Left
- **THEN** all photos remain selected because the new baseline contains the entire library

#### Scenario: Disconnect or replace the library
- **WHEN** the current connection disconnects or a connection attempt clears or replaces its photos
- **THEN** all previous selection and navigation state is discarded and subsequent gestures reference only the new library

#### Scenario: Empty camera library
- **WHEN** the library is empty and the user attempts a range gesture
- **THEN** no photo is selected, no preview opens, and no exception occurs

#### Scenario: Download the new selection
- **WHEN** the user builds a selection with modifier gestures and starts a batch download
- **THEN** the request contains exactly the selected directory/filename keys in displayed order and the visible selected count matches that membership

#### Scenario: Adjust selection while downloading
- **WHEN** the user changes the selection with modifier gestures during an active download
- **THEN** the active operation keeps its original file list and progress, and all additional download actions remain disabled
