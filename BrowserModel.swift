import Cocoa
import Combine

@MainActor
final class BrowserModel: ObservableObject {
    let connection: CameraConnection
    let download: DownloadService
    let images: CameraImageLoader
    @Published private(set) var settings = SettingsSnapshot()
    @Published private(set) var photos: [CameraPhoto] = []
    @Published private(set) var selection = PhotoSelection()
    var selected: Set<CameraPhoto> { selection.selected }
    var active: CameraPhoto? { selection.active }
    @Published private(set) var preview: CameraPhoto?
    @Published var listView = false
    @Published private(set) var progress: DownloadEvent?
    @Published var status = "Connect to your camera to browse photos."
    @Published var target: ConnectionTarget = .currentWiFi
    private var librarySession: String?
    private var targetInitialized = false
    private var selectionRevision = 0
    var onSettingsChanged: (() -> Void)?

    init(connection: CameraConnection, download: DownloadService, images: CameraImageLoader? = nil) {
        self.connection = connection; self.download = download
        self.images = images ?? CameraImageLoader()
        connection.onChange = { [weak self] in self?.refresh() }
        connection.onEvent = { [weak self] in self?.receive($0) }
        connection.preferences.onChange = { [weak self] in self?.refresh() }
        connection.canConnect = { [weak download] in download?.isDownloading == false }
        download.canStart = { [weak connection] in connection?.isConnecting == false }
        download.onEvent = { [weak self] in self?.receive($0) }
        refresh()
    }
    var lifecycle: ConnectionLifecycle { settings.lifecycle }
    var primaryLabel: String { lifecycle.primaryLabel }
    var primaryEnabled: Bool { !download.isDownloading && !lifecycle.draining }
    var targetsEnabled: Bool { !settings.controlsDisabled && !download.isDownloading }
    var canDownload: Bool { connection.isConnected && !connection.isConnecting && !download.isDownloading }
    var selectedFiles: [String] { photos.filter { selected.contains($0) }.map(\.path) }
    var currentLabel: String {
        if let current = settings.current { return "\(current.name) (current)" }
        return settings.wifiReady == false ? "No Wi-Fi connection" : "Current Wi-Fi — name unavailable"
    }
    var networkTargets: [NetworkSnapshot] {
        settings.networks.filter { settings.available.contains($0.id) && $0.id != settings.current?.id }
    }
    func cameraLabel(_ camera: BluetoothSnapshot) -> String {
        let duplicate = settings.cameras.contains { $0.id != camera.id && $0.name == camera.name }
        return camera.name + (duplicate ? " · " + camera.id.uuidString.suffix(6) : "") + " · " + camera.status
    }
    var targetLabel: String {
        switch target {
        case .currentWiFi: return currentLabel
        case .network(let id): return settings.networks.first { $0.id == id }?.network.name ?? currentLabel
        case .bluetooth(let id): return settings.cameras.first { $0.id == id }.map(cameraLabel) ?? "Remembered camera"
        }
    }
    func refresh() {
        settings = connection.settingsSnapshot()
        if settings.selectionRevision != selectionRevision, case .bluetooth = target,
           settings.preferredTarget != target { target = settings.preferredTarget }
        selectionRevision = settings.selectionRevision
        if !targetInitialized {
            target = settings.preferredTarget
            targetInitialized = true
        }
        if case .network(let id) = target, !networkTargets.contains(where: { $0.id == id }) {
            target = .currentWiFi
        }
        if settings.lifecycle.busy, librarySession != nil { clearLibrary() }
        onSettingsChanged?()
    }
    func selectTarget(_ value: ConnectionTarget) {
        guard targetsEnabled, connection.selectTarget(value) else { return }
        target = value
    }
    func useManualWiFi() {
        selectTarget(.currentWiFi)
        status = "Turn on camera Wi-Fi and join it on your Mac, then press CONNECT."
    }
    func primaryAction() {
        guard primaryEnabled else { return }
        switch lifecycle {
        case .idle:
            clearLibrary()
            connection.connect(id: UUID().uuidString, target: target)
        case .connecting: connection.cancelConnection()
        case .connected: connection.disconnectSession()
        case .draining: break
        }
        refresh()
    }
    func receive(_ event: ConnectionEvent) {
        guard event.id == connection.lastEvent?.id else { return }
        status = [event.message, event.warning].filter { !$0.isEmpty }.joined(separator: " ")
        switch event.phase {
        case .completed:
            clearLibrary()
            librarySession = event.id
            photos = event.photos
        case .disconnected: clearLibrary()
        default: break
        }
        refresh()
    }
    func receive(_ event: DownloadEvent) {
        guard event.id == download.lastEvent?.id else { return }
        progress = event.phase.terminal ? nil : event
        if event.phase.terminal { status = event.message ?? event.phase.label }
        // Admission is owned by DownloadService, including the picker interval.
        objectWillChange.send()
    }
    func requestDownload(_ files: [String]) {
        let valid = Set(photos.map(\.path))
        guard canDownload, !files.isEmpty, files.allSatisfy(valid.contains) else { return }
        download.start(DownloadRequest(id: UUID().uuidString, files: files))
        objectWillChange.send()
    }
    func cancelDownload(id: String) { download.cancelDownload(id: id) }
    func toggle(_ photo: CameraPhoto) {
        guard photos.contains(photo) else { return }
        selection.toggle(photo)
    }
    func selectAll() { selection.bulk(Set(photos)) }
    func toggleSelectAll() {
        if selected.count == photos.count { clearSelection() }
        else { selectAll() }
    }
    func clearSelection() { selection.bulk([]) }
    func focusPhoto(_ photo: CameraPhoto) {
        guard photos.contains(photo) else { return }
        selection.focus(photo)
    }
    func selectRange(to photo: CameraPhoto) { selection.range(to: photo, in: photos) }
    func moveSelection(_ direction: GalleryDirection, columns: Int) {
        selection.move(direction, in: photos, columns: columns, list: listView)
    }
    func openPreview(_ photo: CameraPhoto) {
        guard photos.contains(photo) else { return }
        selection.origin(photo); preview = photo
    }
    func closePreview() { preview = nil }
    func navigatePreview(_ delta: Int) {
        guard let photo = preview, let index = photos.firstIndex(of: photo), !photos.isEmpty else { return }
        let next = photos[(index + delta + photos.count) % photos.count]
        selection.origin(next); preview = next
    }
    var previewPosition: String {
        guard let photo = preview, let index = photos.firstIndex(of: photo) else { return "" }
        return "\(photo.file) · \(photo.dir) · \(index + 1)/\(photos.count)"
    }
    private func clearLibrary() {
        photos = []; selection = PhotoSelection(); preview = nil; librarySession = nil
        images.invalidate()
    }
}
