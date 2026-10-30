import Cocoa
import SwiftUI

func descendants<T: NSView>(_ root: NSView, of type: T.Type) -> [T] {
    (root as? T).map { [$0] } ?? [] + root.subviews.flatMap { descendants($0, of: type) }
}
func accessibilityFrame(_ item: NSObject) -> NSRect? {
    guard item.responds(to: NSSelectorFromString("accessibilityFrame")) else { return nil }
    return (item.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue
}
@MainActor func runNativeBrowserTests() {
    let rig = BluetoothRig()
    let transport = FakeImageTransport()
    let loader = CameraImageLoader(transport: transport)
    let output = testRoot.appendingPathComponent("native-browser-output")
    try! fm.createDirectory(at: output, withIntermediateDirectories: true)
    try! rig.prefs.setFolder(output)
    let download = DownloadService(preferences: rig.prefs, cameraBase: fixtureURL, temporaryDirectory: testRoot)
    let controller = AppController(preferences: rig.prefs, download: download, connection: rig.connection, images: loader)
    let model = controller.model
    let photos = [CameraPhoto(dir: "DCIM", file: "one.JPG"), CameraPhoto(dir: "OTHER", file: "one.JPG"),
                  CameraPhoto(dir: "DCIM", file: "quote'\" & <photo>?#%.JPG")]
    rig.camera.result = .success(photos)
    check(model.primaryLabel == "CONNECT" && model.targetsEnabled, "Native initial connection actions")
    model.selectTarget(.bluetooth(rig.id))
    check(rig.radio.prepares == 0 && rig.wifi.joins.isEmpty, "Native selection never connects or wakes")
    model.primaryAction()
    waitFor("native model verified library") { model.photos == photos && model.connection.isConnected }
    check(model.primaryLabel == "DISCONNECT" && !model.targetsEnabled
          && model.settings.bluetoothStatus == "Released", "Verified library and released Bluetooth remain distinct")

    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 360),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    controller.mainWindow = window
    let host = NativeBrowserHostingView(model: model, images: loader, showSettings: controller.showSettings)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    func elements() -> [NSObject] { accessibleElements(host) }
    func element(_ label: String) -> NSObject? { elements().first { accessibilityText($0, "accessibilityLabel") == label } }
    waitFor("native header accessibility") { element("Refresh cameras list") != nil && element("Settings") != nil }
    func routeImage() -> NSImage? {
        descendants(host, of: NSButton.self).first { $0.title == model.targetLabel }?.image
    }
    waitFor("Bluetooth selector supplies an image to the native menu button") { routeImage() != nil }
    let bluetoothImage = routeImage()
    check(element("Bluetooth connection target") != nil && element("DISCONNECT") != nil, "Native route and lifecycle accessible controls: \(elements().compactMap { accessibilityText($0, "accessibilityLabel") })")
    let header = ["Bluetooth connection target", "Refresh cameras list", "DISCONNECT", "Settings"].compactMap { element($0).flatMap(accessibilityFrame) }
    let content = window.convertToScreen(host.convert(host.bounds, to: nil))
    check(header.count == 4 && header.allSatisfy { $0.minX >= content.minX - 1 && $0.maxX <= content.maxX + 1 }
          && header.map(\.midY).max()! - header.map(\.midY).min()! < 4,
          "Header controls fit one line at 480 points: \(header), content \(content)")
    waitFor("visible thumbnails demand") { transport.requests.count > 0 }
    var completed = Set<Int>()
    func completeImages() {
        for index in transport.requests.indices where completed.insert(index).inserted { transport.finish(index, .success(fixturePNG())) }
    }
    waitFor("visible image pipeline settles") { completeImages(); return loader.activeCount == 0 }
    let loadedRequests = transport.requests.count
    let generation = loader.generation
    model.toggle(photos[1]); model.toggle(photos[0]); model.toggle(photos[0]); model.toggle(photos[0])
    check(model.selectedFiles == [photos[0].path, photos[1].path] && model.selected.count == 2,
          "Duplicate basenames retain distinct membership and displayed-order requests")
    let settle = Date().addingTimeInterval(0.15)
    waitFor("selection-only rendering") { Date() >= settle }
    check(loader.generation == generation && transport.requests.count == loadedRequests, "Selection updates reuse loaded thumbnail demand/cache")
    model.listView = true
    waitFor("list layout") { element("Select " + photos[2].file) != nil }
    completeImages()
    check(model.selected.count == 2 && model.active == photos[0], "Grid/list retains valid selection and active identity")
    check(element("Preview " + photos[2].file) != nil, "Punctuation camera text is literal native accessibility text")

    model.openPreview(photos[0])
    waitFor("preview owns responder") { window.firstResponder is PreviewKeyResponder }
    func sendKey(_ code: UInt16, _ text: String, modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        window.sendEvent(event)
    }
    sendKey(124, "\u{f703}")
    waitFor("actual preview Right event") { model.preview == photos[1] }
    sendKey(123, "\u{f702}")
    waitFor("actual preview Left event") { model.preview == photos[0] }
    // A different native control owns input: preview must not consume its keys.
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
    host.addSubview(field); window.makeFirstResponder(field)
    sendKey(124, "\u{f703}")
    check(model.preview == photos[0], "Preview does not intercept another native field's arrows")
    field.removeFromSuperview()
    let responder = descendants(host, of: PreviewKeyResponder.self).first!
    window.makeFirstResponder(responder)
    model.requestDownload(model.selectedFiles)
    waitFor("native progress above preview") { model.progress?.phase == .downloading }
    model.clearSelection(); model.listView = false; model.navigatePreview(1)
    check(!model.canDownload && !model.primaryEnabled && model.progress?.total == 2,
          "Shared progress and admission survive browsing and selection changes")
    let stale = DownloadEvent(id: "obsolete", phase: .completed, completed: 1, total: 1, filename: "stale.JPG", message: "wrong")
    model.receive(stale)
    check(model.progress != nil && model.status != "wrong", "Native progress rejects old operation events")
    waitFor("shared progress accessible with preview") { element("Active download") != nil && element("Photo preview") != nil }
    if let progress = element("Active download").flatMap(accessibilityFrame), let preview = element("Photo preview").flatMap(accessibilityFrame) {
        check(progress.minY >= preview.maxY - 1, "Download indicator remains above preview")
    } else { check(false, "Progress/preview expose native accessibility frames") }
    waitFor("captured native batch export") { !download.isDownloading }
    check(model.progress == nil && model.status.hasPrefix("Saved:") && (try? fm.contentsOfDirectory(atPath: output.path).count) == 1,
          "Native terminal outcome completes captured ZIP despite selection changes")
    waitFor("preview responder after navigation") { window.firstResponder is PreviewKeyResponder }
    sendKey(53, "\u{1b}")
    waitFor("actual Escape closes preview and restores gallery focus") { model.preview == nil && !(window.firstResponder is PreviewKeyResponder) }
    check(model.active == photos[1], "Preview return retains active identity")
    model.primaryAction()
    check(model.photos.isEmpty && model.selected.isEmpty && model.active == nil && model.preview == nil
          && loader.generation != generation, "Disconnect invalidates library state and images")
    model.requestDownload([photos[0].path])
    check(!download.isDownloading, "A stale original-download action cannot use the disconnected library")
    // Native controls expose cancellation/draining from the actual coordinator.
    rig.radio.hold = true; rig.radio.holdRelease = true
    model.primaryAction()
    waitFor("native connecting") { model.primaryLabel == "CANCEL" }
    model.primaryAction()
    check(model.primaryLabel == "CANCELLING…" && !model.primaryEnabled && !model.canDownload, "Native drain locks independently derived actions")
    rig.radio.pending?(rig.radio.result); rig.radio.releasePending?()
    waitFor("native cancellation drained") { model.primaryLabel == "CONNECT" }
    rig.radio.hold = false; rig.radio.holdRelease = false; rig.radio.result = .failure(BluetoothFailure.rejected)
    model.primaryAction(); waitFor("native manual recovery") { model.settings.manualRecovery && !rig.connection.isConnecting }
    let prepares = rig.radio.prepares
    model.useManualWiFi()
    check(model.target == .currentWiFi && rig.radio.prepares == prepares, "Native manual recovery only selects explicit Wi-Fi route")
    waitFor("Wi-Fi selector image updates") {
        element("Wi-Fi connection target") != nil && routeImage() != nil && routeImage() !== bluetoothImage
    }
    window.close()
    print("PASS: native browser routes/lifecycle, minimum header, stable selection/images, literal text, preview responder/focus, progress, stale events, cancellation and manual recovery")
}
