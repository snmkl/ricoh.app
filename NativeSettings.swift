import Cocoa
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    let preferences: AppPreferences
    let connection: CameraConnection
    @Published private(set) var snapshot: SettingsSnapshot
    @Published var error = ""
    var chooseFolder: () -> Void = {}
    init(preferences: AppPreferences, connection: CameraConnection) {
        self.preferences = preferences; self.connection = connection
        snapshot = connection.settingsSnapshot()
    }
    func refresh() { snapshot = connection.settingsSnapshot() }
    func setFormat(_ value: ExportFormat) { preferences.setFormat(value) }
    func forgetNetwork(_ id: String) { connection.forget(id) }
    func forgetCamera(_ id: UUID) { connection.forgetBluetooth(id.uuidString) }
    func discover() { connection.refresh(requestAuthorization: true) }
    func findCameras() { connection.findBluetooth() }
}

struct NativeSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Downloads") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save folder").font(.headline)
                        Text(model.snapshot.folder.isEmpty ? "Choose a folder before downloading." : model.snapshot.folder)
                            .font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Download folder: " + model.snapshot.folder)
                        Button("Choose folder…", action: model.chooseFolder).accessibilityIdentifier("choose-folder")
                        Picker("Default batch format", selection: Binding(get: { model.snapshot.format }, set: model.setFormat)) {
                            Text("ZIP archive").tag(ExportFormat.zip)
                            Text("Separate files").tag(ExportFormat.separate)
                        }.accessibilityIdentifier("export-format")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Bluetooth cameras") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enable Bluetooth on the camera, choose Pairing, and complete the macOS passkey prompt when connecting. Set Action Mode to On anytime to connect while the camera is off.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(model.snapshot.bluetoothState).font(.caption)
                            Spacer(minLength: 4)
                            Button("Find cameras…", action: model.findCameras)
                                .disabled(model.snapshot.controlsDisabled)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                if model.snapshot.cameras.isEmpty { Text("No Bluetooth cameras remembered yet.").foregroundStyle(.secondary) }
                                ForEach(model.snapshot.cameras) { camera in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(camera.name)
                                            Text(camera.model + " · " + camera.status).font(.caption).foregroundStyle(.secondary)
                                            if !camera.firmware.isEmpty { Text("Firmware " + camera.firmware).font(.caption2) }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        if camera.remembered {
                                            Button { model.forgetCamera(camera.id) } label: { Image(systemName: "trash") }
                                                .disabled(camera.protected)
                                                .accessibilityLabel("Forget Bluetooth camera " + camera.name)
                                                .help("Forget Bluetooth camera " + camera.name)
                                        }
                                    }
                                }
                            }.padding(8)
                        }.frame(height: 132).background(Color.primary.opacity(0.04)).cornerRadius(5)
                            .accessibilityLabel("Remembered and nearby Bluetooth cameras")
                    }.padding(8)
                }
                GroupBox("Known camera networks") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Remembered after a successful camera connection, including networks currently unavailable.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Refresh Wi-Fi discovery", action: model.discover)
                            .disabled(model.snapshot.lifecycle.busy)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                if model.snapshot.networks.isEmpty { Text("No camera networks remembered yet.").foregroundStyle(.secondary) }
                                ForEach(model.snapshot.networks) { entry in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(entry.network.name)
                                            Text("Last connected: " + entry.lastConnected.formatted()).font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Button { model.forgetNetwork(entry.id) } label: { Image(systemName: "trash") }
                                            .disabled(entry.forgetting)
                                            .accessibilityLabel("Forget network " + entry.network.name)
                                            .help("Forget network " + entry.network.name)
                                    }
                                }
                            }.padding(8)
                        }.frame(height: 132).background(Color.primary.opacity(0.04)).cornerRadius(5)
                            .accessibilityLabel("Remembered camera Wi-Fi networks")
                    }.padding(8)
                }
                if !model.snapshot.notice.isEmpty { Text(model.snapshot.notice).font(.caption).fixedSize(horizontal: false, vertical: true) }
                if !model.error.isEmpty { Text(model.error).foregroundStyle(.red).accessibilityLabel("Settings error: " + model.error) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 360).accessibilityIdentifier("settings-form")
    }
}

final class SettingsPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w", attachedSheet == nil {
            performClose(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if attachedSheet == nil { performClose(sender) }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    let hostingView: NSHostingView<NativeSettingsView>
    private var presenting = false
    init(model: SettingsModel) {
        self.model = model
        hostingView = NSHostingView(rootView: NativeSettingsView(model: model))
        let panel = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Settings"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 400, height: 360)
        panel.contentView = hostingView
        super.init(window: panel)
        panel.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(relativeTo parent: NSWindow?) {
        guard !presenting, let window = window, NSApplication.shared.modalWindow == nil,
              let screen = parent?.screen ?? window.screen ?? NSScreen.main else { return }
        presenting = true
        defer { presenting = false }
        model.refresh()
        let responder = parent?.firstResponder
        let visible = screen.visibleFrame
        let chrome = window.frame.height - window.contentLayoutRect.height
        window.setContentSize(NSSize(width: min(480, visible.width), height: min(620, visible.height - chrome)))
        window.center()
        if let parent = parent {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2, y: parent.frame.midY - window.frame.height / 2))
        }
        window.setFrameOrigin(NSPoint(x: max(visible.minX, min(window.frame.minX, visible.maxX - window.frame.width)),
            y: max(visible.minY, min(window.frame.minY, visible.maxY - window.frame.height))))
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.runModal(for: window)
        window.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
        if let responder = responder, parent?.makeFirstResponder(responder) == true { return }
        parent?.makeFirstResponder(parent?.contentView)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.attachedSheet == nil }
    func windowWillClose(_ notification: Notification) {
        if NSApplication.shared.modalWindow === window { NSApplication.shared.stopModal() }
    }
}
