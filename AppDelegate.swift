import Cocoa
import SwiftUI

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let preferences = AppPreferences()
    lazy var downloadHandler = DownloadService(preferences: preferences)
    lazy var controller = AppController(preferences: preferences, download: downloadHandler)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = makeApplicationMenu(settingsTarget: self, action: #selector(showSettings))

        // Window
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let w: CGFloat = min(1200, screenRect.width * 0.85)
        let h: CGFloat = min(800, screenRect.height * 0.85)
        let x = screenRect.midX - w / 2
        let y = screenRect.midY - h / 2

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GR IIIx Browser"
        controller.mainWindow = window
        window.contentView = NSHostingView(rootView: NativeBrowserView(model: self.controller.model,
            images: self.controller.model.images, showSettings: { [weak self] in self?.controller.showSettings() }))
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
        window.minSize = NSSize(width: 480, height: 360)
        window.makeKeyAndOrderFront(nil)

        controller.connection.refresh(requestAuthorization: true)
    }

    @objc func showSettings() { controller.showSettings() }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.connection.refreshCurrentNetwork()
        controller.connection.checkConnection()
        controller.connection.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@MainActor
func makeApplicationMenu(settingsTarget: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: action, keyEquivalent: ",")
        settingsItem.target = settingsTarget
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit GRBrowser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu

}
