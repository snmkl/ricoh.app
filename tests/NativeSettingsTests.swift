import Cocoa
import SwiftUI

func accessibilityText(_ item: NSObject, _ selector: String) -> String? {
    let key = NSSelectorFromString(selector)
    return item.responds(to: key) ? item.perform(key)?.takeUnretainedValue() as? String : nil
}
func accessibleElements(_ root: Any) -> [NSObject] {
    var result: [NSObject] = []
    var queue = [root]
    var seen = Set<ObjectIdentifier>()
    while !queue.isEmpty, result.count < 10000 {
        let next = queue.removeFirst()
        guard let item = next as? NSObject, seen.insert(ObjectIdentifier(item)).inserted else { continue }
        result.append(item)
        let key = NSSelectorFromString("accessibilityChildren")
        if item.responds(to: key), let children = item.perform(key)?.takeUnretainedValue() as? [Any] { queue.append(contentsOf: children) }
    }
    return result
}

@MainActor func runSettingsTests() {
    let rig = BluetoothRig()
    let prefs = rig.prefs
    prefs.remember(cameraA, at: Date(timeIntervalSince1970: 1))
    prefs.remember(cameraB, at: Date(timeIntervalSince1970: 2))
    let output = testRoot.appendingPathComponent("native-modal-output")
    try! fm.createDirectory(at: output, withIntermediateDirectories: true)
    try! prefs.setFolder(output)
    let download = DownloadService(preferences: prefs, cameraBase: fixtureURL, temporaryDirectory: testRoot)
    let controller = AppController(preferences: prefs, download: download, connection: rig.connection)
    let browser = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 360),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
    browser.isReleasedWhenClosed = false
    let browserView = NSView()
    browser.contentView = browserView; controller.mainWindow = browser
    browser.makeKeyAndOrderFront(nil)
    let menu = makeApplicationMenu(settingsTarget: controller, action: #selector(AppController.showSettings))
    func exercise(usingMenu: Bool = false, _ inspect: @escaping @MainActor (SettingsWindowController) -> Void) {
        var inspected = false
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard !inspected, let settings = controller.settingsController,
                      NSApplication.shared.modalWindow === settings.window else { return }
                inspected = true; inspect(settings)
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        if usingMenu {
            let comma = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: browser.windowNumber, context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)!
            check(menu.performKeyEquivalent(with: comma), "Production Settings menu handles Command-comma")
        } else { controller.showSettings() }
        waitFor("native modal settings") { inspected && NSApplication.shared.modalWindow == nil }
        timer.invalidate()
        check(browser.isVisible && controller.settingsController?.window?.isVisible == false, "Settings closes without closing browser")
    }
    exercise(usingMenu: true) { settings in
        let panel = settings.window!
        check(panel.contentView === settings.hostingView && panel.standardWindowButton(.closeButton)?.isHidden == false,
              "Settings uses native hosting and visible close chrome")
        check(panel.screen!.visibleFrame.contains(panel.frame), "Settings constrained to screen")
        check(settings.model.snapshot.folder == output.path && settings.model.snapshot.format == .zip, "Native Settings reads saved values")
        settings.model.setFormat(.separate)
        check(prefs.format == .separate && settings.model.snapshot.format == .separate, "Native format change persists and updates during modal")
        controller.showSettings()
        check(controller.settingsController === settings, "Repeated open reuses one modal")
        let paintDeadline = Date().addingTimeInterval(0.2)
        waitFor("native settings layout and paint") { Date() >= paintDeadline }
        let labels = accessibleElements(settings.hostingView).compactMap { accessibilityText($0, "accessibilityLabel") }
        check(labels.contains("Choose folder…") && labels.contains("Forget network " + cameraA.name),
              "Native Settings exposes folder and named Forget accessibility controls: \(labels)")
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        check(panel.performKeyEquivalent(with: event), "Actual Command-W event dismisses Settings")
    }
    let first = controller.settingsController
    exercise { settings in
        check(settings === first && settings.model.snapshot.format == .separate, "Reopen preserves native model and preferences")
        settings.window?.standardWindowButton(.closeButton)?.performClick(nil)
    }
    var chosenParent: NSWindow?
    let chosen = testRoot.appendingPathComponent("native-chosen-folder")
    try! fm.createDirectory(at: chosen, withIntermediateDirectories: true)
    controller.folderChooser = { parent, _, completion in chosenParent = parent; completion(chosen) }
    exercise { settings in
        settings.model.chooseFolder()
        check(chosenParent === settings.window && prefs.folder()?.path == chosen.path, "Injected folder picker is attached to Settings and persists choice")
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.worksWhenModal = true
        settings.window!.beginSheet(sheet)
        check(!settings.windowShouldClose(settings.window!), "Child sheet protects parent closure")
        settings.window!.cancelOperation(nil)
        check(settings.window!.isVisible, "Escape cannot close parent with attached sheet")
        settings.window!.endSheet(sheet); sheet.orderOut(nil)
        waitFor("child sheet dismissal") { settings.window?.attachedSheet == nil }
        settings.window!.cancelOperation(nil)
    }
    for index in 0..<30 { prefs.remember(CameraNetwork(name: "GR fixture \(index) <&>"), at: Date()) }
    exercise { settings in
        settings.window!.setContentSize(NSSize(width: 400, height: 360))
        settings.hostingView.layoutSubtreeIfNeeded()
        check(settings.hostingView.bounds.width == 400 && settings.hostingView.bounds.height == 360,
              "Native Settings hosts long lists at minimum content size")
        check(settings.model.snapshot.networks.count == 32, "All unavailable history remains represented")
        settings.model.forgetNetwork(cameraA.id)
        waitFor("native network Forget") { !prefs.networks.contains { $0.network.id == cameraA.id } }
        check(rig.connection.devices.cameras.isEmpty && !rig.radio.observations.isEmpty, "Wi-Fi Forget preserves Bluetooth observations")
        settings.window!.cancelOperation(nil)
    }
    try! prefs.setFolder(output)
    download.startDownload(id: "native-modal-export", files: ["DCIM/one.JPG", "DCIM/two.JPG"])
    check(download.isDownloading, "Export reserves admission before presentation")
    exercise { settings in
        settings.model.setFormat(.zip)
        waitFor("fixture export while native Settings modal") {
            !download.isDownloading && (try? fm.contentsOfDirectory(atPath: output.path).count) == 2
        }
        check(controller.model.progress == nil && controller.model.status.hasPrefix("Saved:"), "Native model gets terminal outcome during modal")
        check((try? Data(contentsOf: output.appendingPathComponent("one.JPG")).count) == 2_097_152,
              "Captured separate export completes despite Settings format change")
        settings.window!.cancelOperation(nil)
    }
    browser.close()
    print("PASS: SwiftUI Settings persistence, native modal/keyboard/sheet/reopening, narrow long lists and actual export during modal")
}
