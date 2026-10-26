import Cocoa
import SwiftUI

@MainActor func runSelectionTests() {
    // Repeated basenames across a directory boundary must remain separate identities.
    let photos = (0..<8).map { CameraPhoto(dir: $0 < 4 ? "DCIM" : "OTHER", file: "\($0 % 4).JPG") }
    var selection = PhotoSelection()
    func expect(_ indices: [Int], _ message: String) {
        check(selection.selected == Set(indices.map { photos[$0] }), message)
    }
    selection.toggle(photos[7]); selection.toggle(photos[1])
    selection.range(to: photos[4], in: photos)
    expect([1, 2, 3, 4, 7], "Forward range crosses directories and retains independent choice")
    selection.range(to: photos[3], in: photos)
    expect([1, 2, 3, 7], "Repeated Shift-click contracts using a fixed baseline")
    selection.move(.left, in: photos, columns: 3, list: false)
    selection.move(.left, in: photos, columns: 3, list: false)
    selection.move(.left, in: photos, columns: 3, list: false)
    expect([0, 1, 7], "Keyboard reversal crosses anchor while preserving baseline")
    check(selection.anchor == photos[1] && selection.active == photos[0], "Anchor stays fixed through reversal")
    selection.origin(photos[5]); selection.range(to: photos[2], in: photos)
    expect([0, 1, 2, 3, 4, 5, 7], "New origin ends old session, backward range follows display order")
    selection = PhotoSelection()
    selection.toggle(photos[7]); selection.toggle(photos[3]); selection.toggle(photos[1])
    selection.move(.right, in: photos, columns: 3, list: false)
    selection.move(.right, in: photos, columns: 3, list: false)
    selection.move(.right, in: photos, columns: 3, list: false)
    selection.move(.left, in: photos, columns: 3, list: false)
    selection.move(.left, in: photos, columns: 3, list: false)
    expect([1, 2, 3, 7], "Baseline overlap survives interval contraction and Shift release/repress")
    selection.focus(photos[5]); selection.move(.left, in: photos, columns: 3, list: true)
    check(selection.anchor == photos[5] && selection.selected.contains(photos[4]), "Direct keyboard focus establishes new origin")
    selection.bulk([])
    check(selection.active == photos[4] && selection.anchor == nil && selection.baseline == nil, "Clear retains active, clears range session")
    selection.move(.right, in: photos, columns: 3, list: true)
    expect([4, 5], "Range after Clear starts at retained active")
    selection.bulk(Set(photos)); selection.move(.left, in: photos, columns: 3, list: true)
    expect(Array(0..<8), "Select all becomes baseline for next range")
    selection.bulk([]); selection.move(.right, in: [], columns: 0, list: false)
    expect([], "Empty library ignores navigation")
    selection = PhotoSelection()
    selection.range(to: photos[4], in: photos)
    expect([4], "No-origin Shift-click selects endpoint only")
    check(selection.anchor == photos[4] && selection.active == photos[4], "No-origin click establishes anchor")
    selection = PhotoSelection()
    selection.bulk([photos[7]])
    selection.move(.down, in: photos, columns: 3, list: false)
    expect([0, 7], "No-origin Shift+Arrow initializes first photo with independent baseline")
    selection.range(to: CameraPhoto(dir: "missing", file: "missing"), in: photos)
    expect([0, 7], "Stale endpoint is ignored")
    selection.origin(CameraPhoto(dir: "missing", file: "missing"))
    selection.range(to: photos[2], in: photos)
    expect([0, 2, 7], "Missing origin falls back to clicked endpoint")

    selection = PhotoSelection(); selection.toggle(photos[1]); selection.range(to: photos[3], in: photos)
    selection.move(.right, in: Array(photos.suffix(2)), columns: 3, list: false)
    check(selection.selected == [photos[6]] && selection.anchor == photos[6], "Stale range origins cannot survive a replacement order")

    let short = Array(photos.prefix(7))
    for width: CGFloat in [320, 480, 640, 960] {
        let columns = GalleryMetrics.columns(width: width)
        check(columns == max(1, Int((width - 24 + 10) / 155)), "Shared responsive metrics at \(width)")
        selection = PhotoSelection(); selection.origin(short[1])
        selection.move(.down, in: short, columns: columns, list: false)
        check(selection.active == short[min(6, 1 + columns)], "Vertical navigation uses rendered columns at \(width)")
    }
    selection = PhotoSelection(); selection.origin(short[4])
    selection.move(.down, in: short, columns: 3, list: false)
    check(selection.active == short[6], "Incomplete final row clamps to its last photo")
    selection.move(.down, in: short, columns: 3, list: false)
    selection.move(.right, in: short, columns: 3, list: false)
    check(selection.active == short[6], "Last row/right edge do not wrap")
    selection.origin(short[1]); selection.move(.up, in: short, columns: 3, list: false)
    check(selection.active == short[1] && selection.selected.contains(short[6]), "First row up stays put without changing membership")
    selection.move(.down, in: short, columns: 2, list: false)
    check(selection.active == short[3] && selection.anchor == short[1], "Resize uses new geometry without resetting session")
    selection.move(.down, in: short, columns: 2, list: true)
    check(selection.active == short[4] && selection.anchor == short[1], "View switch uses list step, preserving anchor")
    selection.move(.up, in: short, columns: 2, list: true)
    selection.move(.left, in: short, columns: 2, list: true)
    check(selection.active == short[2], "List Up and Left move backward")
    print("PASS: selection ranges, baselines, origins, missing identities, bulk actions and layout destinations")
}

@MainActor func runNativeSelectionTests() {
    let rig = BluetoothRig()
    let transport = FakeImageTransport()
    let loader = CameraImageLoader(transport: transport)
    let download = DownloadService(preferences: rig.prefs, cameraBase: fixtureURL, temporaryDirectory: testRoot)
    let controller = AppController(preferences: rig.prefs, download: download, connection: rig.connection, images: loader)
    let model = controller.model
    let photos = (0..<64).map { CameraPhoto(dir: $0 < 32 ? "DCIM" : "OTHER", file: "\($0 % 32).JPG") }
    rig.camera.result = .success(photos)
    model.selectTarget(.bluetooth(rig.id)); model.primaryAction()
    waitFor("selection fixture library") { model.photos == photos }
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 650),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; controller.mainWindow = window
    let menu = makeApplicationMenu(settingsTarget: controller, action: #selector(AppController.showSettings))
    let previousMenu = app.mainMenu
    app.mainMenu = menu
    defer { app.mainMenu = previousMenu }
    let host = NativeBrowserHostingView(model: model, images: loader, showSettings: controller.showSettings)
    window.contentView = host; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
    func settle() {
        let until = Date().addingTimeInterval(0.12)
        waitFor("native selection layout") { Date() >= until }
    }
    func items() -> [GalleryItemResponder] { descendants(host, of: GalleryItemResponder.self) }
    func item(_ index: Int) -> GalleryItemResponder {
        waitFor("realized photo \(index)") { items().contains { $0.photo == photos[index] } }
        return items().first { $0.photo == photos[index] }!
    }
    func click(_ index: Int, _ region: String, _ flags: NSEvent.ModifierFlags = []) {
        let view = item(index)
        view.layoutSubtreeIfNeeded()
        let point: NSPoint
        switch region {
        case "checkbox": point = NSPoint(x: view.checkbox.frame.midX, y: view.checkbox.frame.midY)
        case "padding": point = NSPoint(x: view.bounds.width - 3, y: 3)
        case "label": point = NSPoint(x: view.bounds.width / 2, y: model.listView ? 24 : 130)
        default: point = NSPoint(x: model.listView ? 70 : view.bounds.width / 2, y: 45)
        }
        let location = view.convert(point, to: nil)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        settle()
    }
    func key(_ code: UInt16, flags: NSEvent.ModifierFlags = .shift, repeatKey: Bool = false) {
        let text = [123: "\u{f702}", 124: "\u{f703}", 125: "\u{f701}", 126: "\u{f700}", 53: "\u{1b}", 49: " "][Int(code)] ?? ""
        window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: repeatKey, keyCode: code)!)
        settle()
    }
    func selectAllKey() {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0)!
        // CLI fixtures can lack an application key window. Start the menu action
        // at this window's real first responder in that environment.
        let item = menu.items[1].submenu!.items[0]
        if app.keyWindow == nil {
            var responder = window.firstResponder
            while let current = responder, !current.responds(to: item.action!) { responder = current.nextResponder }
            item.target = responder
        }
        defer { item.target = nil }
        _ = menu.performKeyEquivalent(with: event)
        settle()
    }
    waitFor("native gallery input") { !items().isEmpty }
    waitFor("native accessible checkbox label") {
        accessibleElements(host).contains { accessibilityText($0, "accessibilityLabel") == "Select " + photos[0].file }
    }
    settle()
    window.makeFirstResponder(host)
    selectAllKey()
    check(model.selected == Set(photos) && model.active == nil, "Command-A selects the whole library before any photo interaction")
    model.clearSelection()
    for list in [false, true] {
        model.listView = list; settle()
        model.clearSelection(); click(1, "checkbox")
        let focused = window.firstResponder
        selectAllKey(); selectAllKey()
        check(model.selected == Set(photos) && model.selectedFiles == photos.map(\.path),
              "Repeated Command-A selects all photos including offscreen and duplicate basenames, list=\(list)")
        check(window.firstResponder === focused && model.active == photos[1] && model.selection.anchor == nil,
              "Command-A preserves active focus and resets the range session")
        model.clearSelection(); window.makeFirstResponder(item(1).checkbox)
        selectAllKey()
        check(model.selected == Set(photos), "Command-A works from a focused photo checkbox")
        model.toggleSelectAll()
        check(model.selected.isEmpty, "Deselect all button still clears the whole selection")
        model.toggleSelectAll()
        check(model.selected == Set(photos), "Select all button still selects the whole library")
        model.clearSelection()
        for region in ["thumbnail", "label", "padding", "checkbox"] {
            model.clearSelection()
            click(0, region, .command)
            check(model.selected == [photos[0]] && model.preview == nil, "Command-click \(region), list=\(list), toggles once without preview: \(model.selected), preview \(String(describing: model.preview))")
            click(1, region, .command)
            check(model.selected == Set(photos.prefix(2)), "Command-click keeps independent choices")
            click(0, region, .command)
            check(model.selected == [photos[1]], "Command-click removes only its target")
        }
        click(2, "checkbox", [.shift, .command])
        check(model.selected == [photos[0], photos[1], photos[2]] && model.selection.anchor == photos[0],
              "Shift wins combined modifiers on native checkbox")
        click(1, "thumbnail", .shift)
        check(model.selected == [photos[0], photos[1]], "Native repeated Shift-click contracts")
        let target = item(1)
        check(target.isAccessibilitySelected() && target.accessibilityValue() as? String == "Active photo",
              "Native selected and active accessibility presentation follows model: selected=\(target.isAccessibilitySelected()), value=\(String(describing: target.accessibilityValue())), active=\(String(describing: model.active)), photo=\(String(describing: target.photo))")
        model.clearSelection(); settle()
        click(1, "thumbnail")
        check(model.preview == photos[1] && model.selected.isEmpty, "Plain pointer click opens preview without changing selection")
        key(53, flags: [])
        click(1, "checkbox")
        check(model.selected == [photos[1]] && model.preview == nil, "Plain checkbox toggles exactly once without preview")
        click(1, "checkbox")
        check(model.selected.isEmpty, "Plain checkbox removes only its photo")
        check(target.checkbox.accessibilityPerformPress(), "Native checkbox supports AX press")
        check(model.selected == [photos[1]], "Accessible checkbox toggles once")
        window.makeFirstResponder(target.checkbox); key(49, flags: [])
        check(model.selected.isEmpty, "Native keyboard Space activates checkbox once")
        key(49, flags: [])
        check(model.selected == [photos[1]], "Keyboard checkbox remains usable after selection updates")
        check(target.previewButton.accessibilityPerformPress(), "Native preview supports AX press")
        waitFor("accessible preview responder") { window.firstResponder is PreviewKeyResponder }
        check(model.preview == photos[1] && model.selected == [photos[1]], "Accessible preview retains selection")
        selectAllKey()
        check(model.preview == photos[1] && model.selected == [photos[1]], "Preview excludes Command-A gallery selection")
        key(124)
        check(model.preview == photos[1] && model.selected == [photos[1]], "Preview excludes Shift range keys")
        // Preview navigation changes the return origin, even though its old
        // responder originally remembered a different gallery item.
        key(124, flags: []); key(123, flags: [])
        key(53, flags: [])
        waitFor("preview returns active native focus: preview=\(String(describing: model.preview)), active=\(String(describing: model.active)), responder=\(String(describing: window.firstResponder)), pending=\(String(describing: target.focus?.pending)), entryWindow=\(String(describing: target.focus?.entry?.window))") { (window.firstResponder as? GalleryItemResponder)?.photo == photos[1] }
        key(124)
        check(model.selected == [photos[1], photos[2]] && model.selection.anchor == photos[1], "Shift+Right uses returned preview origin")
        key(124, repeatKey: true); key(123)
        check(model.selected == [photos[1], photos[2]], "Key repeat extends and reversal contracts")
        // Releasing Shift is deliberately not an origin transition.
        window.sendEvent(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56)!)
        key(123); key(123)
        check(model.selected == [photos[0], photos[1]] && model.selection.anchor == photos[1], "Release/repress crosses fixed anchor")
        window.makeFirstResponder(item(3)); key(123)
        check(model.selection.anchor == photos[3] && model.active == photos[2], "Direct keyboard item focus establishes origin")
    }
    // Settle all image work already requested. Range changes within loaded items
    // must keep both generation and concrete transport demand unchanged.
    var completed = Set<Int>()
    func finishImages() {
        for i in transport.requests.indices where completed.insert(i).inserted { transport.finish(i, .success(fixturePNG())) }
    }
    waitFor("loaded selection thumbnails") { finishImages(); return loader.activeCount == 0 }
    settle()
    let requestCount = transport.requests.count, generation = loader.generation
    click(1, "checkbox", .command); key(124); key(123); key(124)
    check(loader.generation == generation && transport.requests.count == requestCount, "Repeated native selection reuses image generation and loaded requests")

    for flags: NSEvent.ModifierFlags in [[.shift, .command], [.shift, .option], [.shift, .control]] {
        let selected = model.selected, active = model.active
        key(124, flags: flags)
        check(model.selected == selected && model.active == active, "Additional modifiers are excluded")
    }
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
    field.stringValue = "Editable text"
    host.addSubview(field); window.makeFirstResponder(field)
    let selected = model.selected
    key(124)
    check(model.selected == selected && !(window.firstResponder is GalleryItemResponder), "Editable field owns Shift arrows and updates never steal focus")
    selectAllKey()
    check(model.selected == selected && (window.firstResponder as? NSTextView)?.selectedRange() == NSRange(location: 0, length: field.stringValue.utf16.count),
          "Command-A selects editable text without changing photo membership")
    let button = NSButton(title: "Other control", target: nil, action: nil)
    button.frame = field.frame; host.addSubview(button); window.makeFirstResponder(button); key(125)
    check(model.selected == selected && window.firstResponder === button, "Other native control owns its arrows")
    selectAllKey()
    check(model.selected == Set(photos) && window.firstResponder === button, "Command-A works while a browser toolbar control owns focus")
    model.clearSelection(); selected.forEach { model.toggle($0) }
    button.removeFromSuperview(); field.removeFromSuperview()
    window.makeFirstResponder(item(2))
    let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    window.beginSheet(sheet)
    key(124)
    selectAllKey()
    check(model.selected == selected, "Attached sheet excludes gallery navigation")
    window.endSheet(sheet); sheet.orderOut(nil)
    waitFor("gallery sheet dismissed") { window.attachedSheet == nil }

    // Production menu shortcut stays available with the gallery as responder.
    window.makeFirstResponder(item(2))
    var inspectedModal = false
    let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated {
            guard !inspectedModal, let modal = NSApp.modalWindow else { return }
            inspectedModal = true
            let before = model.selected
            key(124)
            selectAllKey()
            check(model.selected == before, "Settings modal excludes gallery input")
            modal.performClose(nil)
        }
    }
    RunLoop.main.add(timer, forMode: .modalPanel)
    let comma = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)!
    check(menu.performKeyEquivalent(with: comma), "Gallery leaves Command-comma available to Settings menu")
    waitFor("Settings modal range guard") { inspectedModal && NSApp.modalWindow == nil }
    timer.invalidate()

    for width: CGFloat in [500, 350, 670] {
        model.listView = false
        window.setContentSize(NSSize(width: width, height: 650)); settle()
        model.clearSelection(); window.makeFirstResponder(item(1)); key(125)
        let stride = GalleryMetrics.columns(width: width)
        check(model.active == photos[1 + stride], "Actual grid navigation uses resized column count \(stride)")
        let a = item(0).convert(NSPoint.zero, to: host), b = item(stride).convert(NSPoint.zero, to: host)
        check(abs(a.y - b.y) > 100, "Rendered grid uses navigation stride")
        let anchor = model.selection.anchor, baseline = model.selection.baseline
        model.listView = true; settle()
        let endpoint = model.active!
        window.makeFirstResponder(items().first { $0.photo == endpoint }!)
        key(125)
        check(model.active == photos[2 + stride] && model.selection.anchor == anchor && model.selection.baseline == baseline,
              "Actual list switch retains range and moves one item")
    }
    // Move beyond the initial lazy viewport using real repeated responder events.
    model.listView = true; settle()
    model.clearSelection(); window.makeFirstResponder(item(2))
    for _ in 0..<38 { key(125, repeatKey: true) }
    check(model.active == photos[40] && model.selection.anchor == photos[2], "Lazy range keeps fixed anchor while crossing directory: active=\(String(describing: model.active)), anchor=\(String(describing: model.selection.anchor)), responder=\(String(describing: window.firstResponder))")
    let endpoint = item(40)
    check(window.firstResponder === endpoint && endpoint.visibleRect.height > 0, "Offscreen endpoint is realized, visible and focused")
    check(endpoint.isAccessibilitySelected(), "Lazy endpoint exposes selected accessibility state")
    let files = model.selectedFiles
    check(files == Array(photos[2...40]).map(\.path), "Range download keys and count follow displayed order")
    check(accessibleElements(host).contains { element in
        ["accessibilityLabel", "accessibilityValue"].contains { key in
            ["39 photos selected", "39 selected"].contains(accessibilityText(element, key) ?? "")
        }
    }, "Visible accessible selected count matches membership")
    // An actual three-column layout with a short final row must clamp Down,
    // consume boundary events, and keep the endpoint focused.
    model.listView = false
    window.setContentSize(NSSize(width: 500, height: 650)); settle()
    let galleryEntry = descendants(host, of: GalleryKeyResponder.self).first { !($0 is GalleryItemResponder) }!
    window.makeFirstResponder(galleryEntry); model.focusPhoto(photos[61]); settle(); key(125)
    check(model.active == photos[63], "Native Down clamps to incomplete final row")
    let finalSelection = model.selected
    key(125); key(124)
    check(model.active == photos[63] && model.selected == finalSelection, "Native final row and library boundaries preserve membership")
    check((window.firstResponder as? GalleryItemResponder)?.photo == photos[63], "Boundary retains endpoint keyboard focus")
    let output = testRoot.appendingPathComponent("selection-export")
    try! fm.createDirectory(at: output, withIntermediateDirectories: true)
    try! rig.prefs.setFolder(output)
    // Use a short, explicit gesture-built batch to keep fixture export fast.
    model.clearSelection(); model.toggle(photos[3]); model.selectRange(to: photos[4])
    let captured = model.selectedFiles
    model.requestDownload(captured)
    waitFor("selection export progress") { model.progress?.phase == .downloading }
    let operationID = model.progress!.id
    model.selectRange(to: photos[7]); model.selectAll(); model.requestDownload(model.selectedFiles)
    check(model.progress?.id == operationID && model.progress?.total == 2 && !model.canDownload && !model.primaryEnabled,
          "Selection changes preserve captured progress and download admission")
    waitFor("selection captured export") { !download.isDownloading }
    let archives = try! fm.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
    check(archives.count == 1 && model.status.hasPrefix("Saved:"), "Only original selection batch exports")
    let listing = Process(); let pipe = Pipe()
    listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); listing.arguments = ["-Z1", archives[0].path]; listing.standardOutput = pipe
    try! listing.run(); listing.waitUntilExit()
    let entries = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    check(captured.allSatisfy { entries.contains($0.components(separatedBy: "/").last!) } && !entries.contains("7.JPG"), "Archive retains captured files after range changes")
    model.primaryAction()
    check(model.photos.isEmpty && model.selected.isEmpty && model.active == nil && model.selection.anchor == nil && model.selection.baseline == nil,
          "Disconnect clears entire selection session")
    rig.camera.result = .success(Array(photos.suffix(2)))
    model.primaryAction(); waitFor("replacement library") { model.photos == Array(photos.suffix(2)) }
    check(model.active == nil && model.selection.baseline == nil && model.selected.isEmpty, "Reconnect never reuses old identities or anchor")
    settle()
    let entry = descendants(host, of: GalleryKeyResponder.self).first { !($0 is GalleryItemResponder) }!
    window.makeFirstResponder(entry); key(124)
    check(model.active == photos[62] && model.selected == [photos[62]], "Replacement initializes navigation from its first photo")
    model.primaryAction(); rig.camera.result = .success([])
    model.primaryAction(); waitFor("empty camera fixture") { rig.connection.isConnected }
    model.moveSelection(.right, columns: 3); model.selectRange(to: photos[0]); model.toggle(photos[0]); model.selectAll()
    settle(); window.makeFirstResponder(host); selectAllKey()
    check(model.photos.isEmpty && model.selected.isEmpty && model.active == nil, "Empty native library ignores stale actions")
    window.close()
    print("PASS: native modifier regions, AX actions, key repeat/focus, guards, resized grids, lazy scrolling, captured export and library resets")
}
