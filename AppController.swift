import Cocoa

@MainActor
final class AppController: NSObject {
    weak var mainWindow: NSWindow?
    let preferences: AppPreferences
    let connection: CameraConnection
    let model: BrowserModel
    let settingsModel: SettingsModel
    var folderChooser: (NSWindow?, URL?, @escaping (URL?) -> Void) -> Void = pickDownloadFolder
    private var choosingFolder = false
    private var connectionTimer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private(set) var settingsController: SettingsWindowController?
    private var settingsScheduled = false

    init(preferences: AppPreferences, download: DownloadService, connection: CameraConnection? = nil, images: CameraImageLoader? = nil) {
        self.preferences = preferences
        self.connection = connection ?? CameraConnection(preferences: preferences)
        self.model = BrowserModel(connection: self.connection, download: download, images: images)
        self.settingsModel = SettingsModel(preferences: preferences, connection: self.connection)
        super.init()
        download.folderChooser = { [weak self] done in
            guard let self = self else { done(nil); return }
            self.chooseDownloadFolder(done)
        }
        settingsModel.chooseFolder = { [weak self] in self?.chooseSettingsFolder() }
        model.onSettingsChanged = { [weak self] in self?.refreshSettings() }
        self.connection.passwordPrompt = { [weak self] name, completion in
            self?.promptPassword(for: name, completion: completion)
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.connection.poll(discover: NSApplication.shared.isActive) }
        }
        connectionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.connection.computerWillSleep() } }
    }
    deinit {
        connectionTimer?.invalidate()
        if let observer = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func refreshSettings() { settingsModel.refresh() }
    @objc func showSettings() {
        guard !settingsScheduled, NSApplication.shared.modalWindow == nil, mainWindow?.attachedSheet == nil else { return }
        if settingsController == nil { settingsController = SettingsWindowController(model: settingsModel) }
        settingsScheduled = true
        // Enter the modal from the run loop so asynchronous service updates continue.
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.settingsScheduled = false
                guard NSApplication.shared.modalWindow == nil, self.mainWindow?.attachedSheet == nil else { return }
                self.refreshSettings()
                self.connection.refresh()
                self.settingsController?.present(relativeTo: self.mainWindow)
            }
        }
    }
    private func showError(_ error: Error) {
        model.status = error.localizedDescription
        settingsModel.error = error.localizedDescription
    }
    func chooseSettingsFolder() {
        let parent = settingsController?.window ?? mainWindow
        guard !choosingFolder, parent?.attachedSheet == nil else { return }
        choosingFolder = true
        folderChooser(parent, preferences.folder()) { [weak self] url in
            guard let self = self else { return }
            self.choosingFolder = false
            if let url = url {
                do { try self.preferences.setFolder(url) } catch { self.showError(error) }
            }
                self.refreshSettings()
        }
    }
    private func chooseDownloadFolder(_ completion: @escaping (URL?) -> Void) {
        let parent = settingsController?.window?.isVisible == true ? settingsController?.window : mainWindow
        guard !choosingFolder, parent?.attachedSheet == nil else { completion(nil); return }
        choosingFolder = true
        folderChooser(parent, preferences.folder()) { [weak self] url in
            self?.choosingFolder = false
            completion(url)
        }
    }
    private func promptPassword(for name: String, completion: @escaping ((String, Bool)?) -> Void) {
        let parent = settingsController?.window?.isVisible == true ? settingsController?.window : mainWindow
        guard parent?.attachedSheet == nil else { completion(nil); return }
        let alert = NSAlert()
        alert.messageText = "Join \(name)"
        alert.informativeText = "Enter the camera Wi-Fi password. Your Mac will switch to this network."
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 65))
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 35, width: 300, height: 24))
        field.placeholderString = "Wi-Fi password"
        field.setAccessibilityLabel("Camera Wi-Fi password")
        let remember = NSButton(checkboxWithTitle: "Remember password in Keychain", target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        remember.state = .off
        view.addSubview(field); view.addSubview(remember)
        alert.accessoryView = view
        alert.window.initialFirstResponder = field
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            let answer = response == .alertFirstButtonReturn ? (field.stringValue, remember.state == .on) : nil
            field.stringValue = ""
            completion(answer)
        }
        if let window = parent { alert.beginSheetModal(for: window, completionHandler: respond) }
        else { respond(alert.runModal()) }
    }
}
