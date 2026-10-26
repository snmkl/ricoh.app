import Cocoa
import SwiftUI

// Route the standard menu action through the browser's responder chain so text
// fields keep their own Select All behavior and other windows stay independent.
@MainActor
final class NativeBrowserHostingView: NSHostingView<NativeBrowserView>, NSMenuItemValidation {
    private var model: BrowserModel?
    convenience init(model: BrowserModel, images: CameraImageLoader, showSettings: @escaping () -> Void) {
        self.init(rootView: NativeBrowserView(model: model, images: images, showSettings: showSettings))
        self.model = model
    }
    private var canSelectAll: Bool {
        guard let model = model else { return false }
        return !model.photos.isEmpty && model.preview == nil && NSApp.modalWindow == nil && window?.attachedSheet == nil
    }
    override func selectAll(_ sender: Any?) {
        guard canSelectAll else { return }
        model?.selectAll()
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(selectAll(_:)) { return canSelectAll }
        return super.validateUserInterfaceItem(item)
    }
}

@MainActor
struct CameraImageView: View {
    let photo: CameraPhoto
    let rendition: ImageRendition
    @ObservedObject var loader: CameraImageLoader
    @State private var image: NSImage?
    @State private var failed = false
    @State private var cancel: (() -> Void)?
    var body: some View {
        ZStack {
            Color.primary.opacity(0.04)
            if let image = image {
                Image(nsImage: image).resizable().scaledToFit().accessibilityHidden(true)
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("Image unavailable").font(.caption)
                }.foregroundStyle(.secondary).accessibilityLabel("Image unavailable for " + photo.file)
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("Loading " + photo.file)
            }
        }
        .onAppear(perform: load)
        .onDisappear { cancel?(); cancel = nil; image = nil }
        .contextMenu { if failed { Button("Retry image", action: load) } }
    }
    private func load() {
        cancel?(); cancel = nil; image = nil; failed = false
        cancel = loader.request(photo, rendition: rendition) { result in
            switch result { case .success(let loaded): image = loaded; case .failure: failed = true }
        }
    }
}

enum BluetoothRouteIcon {
    // Native menus extract images from their labels; a SwiftUI Path is discarded.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 14, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 6, y: 1)); path.line(to: NSPoint(x: 6, y: 17))
            path.line(to: NSPoint(x: 12, y: 12)); path.line(to: NSPoint(x: 1, y: 4))
            path.move(to: NSPoint(x: 6, y: 1)); path.line(to: NSPoint(x: 12, y: 6))
            path.line(to: NSPoint(x: 1, y: 14))
            path.lineWidth = 1.5
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

struct DownloadProgressView: View {
    let event: DownloadEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.phase.label).font(.caption.bold())
                Spacer()
                Text("\(event.completed)/\(event.total) files").font(.caption.monospacedDigit())
            }
            if event.phase == .downloading, let fraction = event.fraction {
                ProgressView(value: fraction).accessibilityLabel("Download progress")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            } else { ProgressView().progressViewStyle(.linear).accessibilityLabel(event.phase.label) }
            Text(event.filename).font(.caption2).lineLimit(1).truncationMode(.middle).help(event.filename)
        }.padding(10).background(Color.accentColor.opacity(0.14)).cornerRadius(6)
            .accessibilityElement(children: .contain).accessibilityLabel("Active download")
    }
}

// A responder local to the preview; selectors, fields, Settings and sheets retain their own keys.
final class PreviewKeyResponder: NSView {
    var handle: (UInt16) -> Void = { _ in }
    var onRestore: (() -> Void)?
    private weak var previous: NSResponder?
    var focusRevision = 0 { didSet { if oldValue != focusRevision { focus() } } }
    var photo: CameraPhoto? {
        didSet { if oldValue != photo { focus() } }
    }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); focus() }
    private func focus() {
        guard let window = window, photo != nil else { return }
        if window.firstResponder !== self { previous = window.firstResponder }
        window.makeFirstResponder(self)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { restoreFocus() }
        super.viewWillMove(toWindow: newWindow)
    }
    func restoreFocus() {
        guard let window = window, window.firstResponder === self else { return }
        if let onRestore = onRestore { onRestore(); return }
        if let view = previous as? NSView, view.window === window { window.makeFirstResponder(view) }
        else { window.makeFirstResponder(window.contentView) }
    }
    override func keyDown(with event: NSEvent) {
        guard window?.firstResponder === self,
              NSApplication.shared.modalWindow == nil, window?.attachedSheet == nil,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              [53, 123, 124].contains(event.keyCode) else { super.keyDown(with: event); return }
        handle(event.keyCode)
    }
}
struct PreviewKeyboard: NSViewRepresentable {
    let photo: CameraPhoto
    let focusRevision: Int
    var restore: (() -> Void)? = nil
    let handle: (UInt16) -> Void
    func makeNSView(context: Context) -> PreviewKeyResponder { PreviewKeyResponder() }
    func updateNSView(_ view: PreviewKeyResponder, context: Context) { view.handle = handle; view.onRestore = restore; view.photo = photo; view.focusRevision = focusRevision }
    static func dismantleNSView(_ view: PreviewKeyResponder, coordinator: ()) { view.restoreFocus() }
}

// Input stays in the gallery responder chain. No application-wide event monitors.
@MainActor
final class GalleryFocus: ObservableObject {
    let items = NSHashTable<GalleryItemResponder>.weakObjects()
    weak var entry: GalleryKeyResponder?
    var pending: CameraPhoto?
    var restoring = false
    private weak var requestedFrom: NSResponder?
    private var returningFromPreview = false
    var ownsFocus: Bool {
        guard let responder = entry?.window?.firstResponder else { return false }
        return responder === entry || items.allObjects.contains { $0.ownsKeyboard }
    }
    func navigate(_ direction: GalleryDirection, model: BrowserModel, columns: Int) {
        // Keep an enduring responder while lazy layout recycles the old endpoint.
        // Once the destination exists, restore() transfers focus to its item.
        if ownsFocus, let entry = entry { entry.window?.makeFirstResponder(entry) }
        let previous = model.active
        model.moveSelection(direction, columns: columns)
        if previous == model.active { restore(model.active) }
    }
    func restore(_ photo: CameraPhoto?, afterPreview: Bool = false) {
        returningFromPreview = afterPreview
        pending = photo
        requestedFrom = entry?.window?.firstResponder
        fulfill()
    }
    func fulfill() {
        guard let photo = pending, let item = items.allObjects.first(where: { $0.photo == photo && $0.window != nil }),
              let window = item.window, NSApp.modalWindow == nil, window.attachedSheet == nil else { return }
        let previewReturn = returningFromPreview && (window.firstResponder === window || window.firstResponder === window.contentView || window.firstResponder is PreviewKeyResponder || window.firstResponder == nil)
        guard window.firstResponder === requestedFrom || ownsFocus || previewReturn else { pending = nil; return }
        restoring = true
        window.makeFirstResponder(item)
        restoring = false
        pending = nil
    }
}

class GalleryKeyResponder: NSView {
    var enabled: () -> Bool = { false }
    var move: (GalleryDirection) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }
    var ownsKeyboard: Bool { window?.firstResponder === self }
    override func keyDown(with event: NSEvent) {
        guard ownsKeyboard, enabled(), NSApp.modalWindow == nil,
              window?.attachedSheet == nil, event.modifierFlags.contains(.shift),
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let direction = GalleryDirection(keyCode: event.keyCode) else {
            super.keyDown(with: event); return
        }
        move(direction)
    }
}

// Native buttons retain keyboard/AX press actions. Pointer input goes through one
// dispatcher, so a modified checkbox never also performs its ordinary toggle.
final class GalleryButton: NSButton {
    var click: (NSEvent.ModifierFlags) -> Void = { _ in }
    var drawsContent = true
    var spokenLabel = ""
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { spokenLabel }
    override func accessibilityTitle() -> String? { spokenLabel }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { (superview as? GalleryItemResponder)?.directFocus() }
        return accepted
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift), GalleryDirection(keyCode: event.keyCode) != nil {
            (superview as? GalleryItemResponder)?.keyDown(with: event)
        } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction(action, to: target)
    }
    override func draw(_ dirtyRect: NSRect) { if drawsContent { super.draw(dirtyRect) } }
    override func mouseDown(with event: NSEvent) { click(event.modifierFlags) }
}

final class GalleryItemResponder: GalleryKeyResponder {
    var photo: CameraPhoto?
    weak var focus: GalleryFocus?
    var directFocus: () -> Void = {}
    var interact: (Bool, NSEvent.ModifierFlags) -> Void = { _, _ in }
    let previewButton = GalleryButton()
    let checkbox = GalleryButton(checkboxWithTitle: "", target: nil, action: nil)
    var list = false
    override var ownsKeyboard: Bool {
        super.ownsKeyboard || window?.firstResponder === previewButton || window?.firstResponder === checkbox
    }
    override var isFlipped: Bool { true }
    override func accessibilityChildren() -> [Any]? { [previewButton, checkbox] }
    override init(frame: NSRect) {
        super.init(frame: frame)
        previewButton.drawsContent = false
        previewButton.target = self; previewButton.action = #selector(previewAction)
        checkbox.target = self; checkbox.action = #selector(checkboxAction)
        previewButton.click = { [weak self] flags in self?.dispatch(checkbox: false, flags: flags) }
        checkbox.click = { [weak self] flags in self?.dispatch(checkbox: true, flags: flags) }
        addSubview(previewButton); addSubview(checkbox)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        previewButton.frame = bounds
        checkbox.frame = NSRect(x: list ? 8 : 7, y: list ? (bounds.height - 20) / 2 : bounds.height - 27,
                                width: 20, height: 20)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Leave the image's existing secondary-click Retry menu reachable.
        if NSApp.currentEvent?.type == .rightMouseDown { return nil }
        let local = convert(point, from: superview)
        guard !isHidden, bounds.contains(local) else { return nil }
        return checkbox.frame.contains(local) ? checkbox : previewButton
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted && focus?.restoring != true { directFocus() }
        return accepted
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focus?.fulfill()
    }
    private func dispatch(checkbox: Bool, flags: NSEvent.ModifierFlags) {
        guard NSApp.modalWindow == nil, window?.attachedSheet == nil, enabled() else { return }
        focus?.restoring = true
        window?.makeFirstResponder(self)
        focus?.restoring = false
        interact(checkbox, flags)
    }
    private func nativeAction(checkbox: Bool) {
        guard NSApp.modalWindow == nil, window?.attachedSheet == nil, enabled() else { return }
        // Keyboard and accessibility activation preserve the control's responder.
        interact(checkbox, [])
    }
    @objc private func previewAction() { nativeAction(checkbox: false) }
    @objc private func checkboxAction() { nativeAction(checkbox: true) }
}

struct GalleryEntry: NSViewRepresentable {
    let focus: GalleryFocus
    let enabled: () -> Bool
    let move: (GalleryDirection) -> Void
    func makeNSView(context: Context) -> GalleryKeyResponder { GalleryKeyResponder() }
    func updateNSView(_ view: GalleryKeyResponder, context: Context) {
        focus.entry = view; view.enabled = enabled; view.move = move
        view.setAccessibilityLabel("Camera photo gallery")
    }
}

struct GalleryItemInput: NSViewRepresentable {
    let photo: CameraPhoto
    @ObservedObject var model: BrowserModel
    let focus: GalleryFocus
    let columns: Int
    func makeNSView(context: Context) -> GalleryItemResponder {
        let view = GalleryItemResponder()
        view.focus = focus; focus.items.add(view)
        return view
    }
    func updateNSView(_ view: GalleryItemResponder, context: Context) {
        view.photo = photo; view.list = model.listView
        view.enabled = { model.preview == nil }
        view.directFocus = { model.focusPhoto(photo) }
        view.move = { focus.navigate($0, model: model, columns: columns) }
        view.interact = { checkbox, flags in
            if flags.contains(.shift) { model.selectRange(to: photo) }
            else if flags.contains(.command) || checkbox { model.toggle(photo) }
            else { model.openPreview(photo) }
        }
        view.checkbox.state = model.selected.contains(photo) ? .on : .off
        view.checkbox.spokenLabel = "Select " + photo.file
        view.previewButton.spokenLabel = "Preview " + photo.file
        view.setAccessibilityLabel(photo.file + " · " + photo.dir)
        view.setAccessibilitySelected(model.selected.contains(photo))
        view.setAccessibilityValue(model.active == photo ? "Active photo" : "")
        view.needsLayout = true
        // Finish lazy endpoint focus after the representable joins its host window.
        DispatchQueue.main.async { [weak focus] in focus?.fulfill() }
    }
}

@MainActor
struct NativeBrowserView: View {
    @StateObject var model: BrowserModel
    @StateObject var images: CameraImageLoader
    let showSettings: () -> Void
    @StateObject private var galleryFocus = GalleryFocus()
    @State private var previewFocusRevision = 0
    private var bluetoothTarget: Bool { if case .bluetooth = model.target { return true }; return false }
    var body: some View {
        VStack(spacing: 0) {
            header.padding(12)
            Divider()
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(model.connection.isConnected ? .green : .secondary).frame(width: 6, height: 6).padding(.top, 5)
                Text(model.status).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2).help(model.status).accessibilityLabel("Camera status: " + model.status)
                if model.settings.manualRecovery {
                    Button("Use manual Wi-Fi", action: model.useManualWiFi).font(.caption)
                        .disabled(!model.targetsEnabled)
                }
            }.padding(.horizontal, 12).padding(.vertical, 7)
            if let progress = model.progress { DownloadProgressView(event: progress).padding(.horizontal, 12).padding(.bottom, 6) }
            HStack(spacing: 8) {
                Text("View").fixedSize()
                Picker("View", selection: $model.listView) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 68).accessibilityLabel("Gallery view")
                Button(model.selected.count == model.photos.count && !model.photos.isEmpty ? "Deselect all" : "Select all", action: model.toggleSelectAll)
                    .disabled(model.photos.isEmpty)
                Button(action: model.clearSelection) { Image(systemName: "xmark.circle") }
                    .disabled(model.selected.isEmpty).accessibilityLabel("Clear selection").help("Clear selection")
                Spacer(minLength: 2)
                Text("\(model.selected.count) selected").font(.caption).accessibilityLabel("\(model.selected.count) photos selected")
                Button("Download") { model.requestDownload(model.selectedFiles) }
                    .disabled(model.selected.isEmpty || !model.canDownload).accessibilityLabel("Download selected photos")
            }.controlSize(.small).padding(.horizontal, 12).padding(.bottom, 7)
            ZStack {
                gallery
                if let photo = model.preview { preview(photo).transition(.opacity).zIndex(1) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onChange(of: model.photos) { _ in galleryFocus.pending = nil }
        .accessibilityIdentifier("camera-browser")
    }
    private var header: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Menu {
                Picker("Connection target", selection: Binding(get: { model.target }, set: { model.selectTarget($0) })) {
                    Section("Current Wi-Fi") { Text(model.currentLabel).tag(ConnectionTarget.currentWiFi) }
                    if !model.settings.cameras.isEmpty {
                        Section("Bluetooth cameras") {
                            ForEach(model.settings.cameras) { camera in
                                Text(model.cameraLabel(camera)).tag(ConnectionTarget.bluetooth(camera.id))
                            }
                        }
                    }
                    if !model.networkTargets.isEmpty {
                        Section("Camera Wi-Fi networks") {
                            ForEach(model.networkTargets) { network in Text(network.network.name).tag(ConnectionTarget.network(network.id)) }
                        }
                    }
                }.labelsHidden().pickerStyle(.inline)
            } label: {
                Label {
                    Text(model.targetLabel).lineLimit(1).truncationMode(.middle)
                } icon: {
                    if bluetoothTarget { Image(nsImage: BluetoothRouteIcon.image) }
                    else { Image(systemName: "wifi") }
                }
            }.menuStyle(.borderedButton).labelStyle(.titleAndIcon)
                .frame(minWidth: 80, idealWidth: 280, maxWidth: 320)
                .layoutPriority(-1).disabled(!model.targetsEnabled)
                .help((bluetoothTarget ? "Bluetooth · " : "Wi-Fi · ") + model.targetLabel)
                .accessibilityLabel(bluetoothTarget ? "Bluetooth connection target" : "Wi-Fi connection target")
                .accessibilityValue(model.targetLabel)
            Button { model.connection.findBluetooth() } label: { Label("Find cameras…", systemImage: "magnifyingglass") }
                .fixedSize().help("Find nearby Ricoh cameras using Bluetooth")
                .accessibilityLabel("Find cameras").disabled(!model.targetsEnabled)
            Button(model.primaryLabel, action: model.primaryAction)
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).frame(width: 100)
                .disabled(!model.primaryEnabled).accessibilityLabel(model.primaryLabel)
            Button(action: showSettings) { Image(systemName: "gearshape") }.help("Settings (⌘,)").accessibilityLabel("Settings")
        }.controlSize(.small)
    }
    private var gallery: some View {
        GeometryReader { geometry in
            let columns = GalleryMetrics.columns(width: geometry.size.width)
            Group {
                if model.photos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "camera").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text(model.connection.isConnected ? "No photos on this camera." : "Connect to your camera to browse photos.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            if model.listView {
                                LazyVStack(spacing: 8) {
                                    ForEach(model.photos) { photo in photoItem(photo, columns: columns) }
                                }.padding(GalleryMetrics.padding)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GalleryMetrics.spacing), count: columns), spacing: GalleryMetrics.spacing) {
                                    ForEach(model.photos) { photo in photoItem(photo, columns: columns) }
                                }.padding(GalleryMetrics.padding)
                            }
                        }.accessibilityLabel("Camera photo gallery")
                            .background(GalleryEntry(focus: galleryFocus, enabled: { model.preview == nil }) {
                                galleryFocus.navigate($0, model: model, columns: columns)
                            }.frame(width: 0, height: 0))
                            .onChange(of: model.active) { photo in
                                if galleryFocus.ownsFocus, let photo = photo {
                                    proxy.scrollTo(photo)
                                    galleryFocus.restore(photo)
                                }
                            }
                            .onChange(of: model.preview) { photo in
                                if photo == nil, let active = model.active { proxy.scrollTo(active) }
                            }
                    }
                }
            }
        }
    }
    private func thumbnail(_ photo: CameraPhoto) -> some View {
        CameraImageView(photo: photo, rendition: .thumbnail, loader: images)
            .id(CameraImageKey(generation: images.generation, photo: photo, rendition: .thumbnail))
    }
    private func photoItem(_ photo: CameraPhoto, columns: Int) -> some View {
        ZStack {
            photoContent(photo).accessibilityHidden(true)
            GalleryItemInput(photo: photo, model: model, focus: galleryFocus, columns: columns)
        }
            .help(photo.path)
            .background(model.selected.contains(photo) ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.03))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.selected.contains(photo) ? Color.accentColor : Color.clear, lineWidth: 1).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 4).inset(by: 3).stroke(model.active == photo ? Color.white.opacity(0.85) : Color.clear, lineWidth: 2).allowsHitTesting(false))
            .id(photo)
    }
    private func photoContent(_ photo: CameraPhoto) -> some View {
        Group {
            if model.listView {
                HStack(spacing: 10) {
                    Color.clear.frame(width: 20)
                    thumbnail(photo).frame(width: 80, height: 54).clipped()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(photo.file).lineLimit(1).truncationMode(.middle)
                        Text(photo.dir).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(7).frame(height: 68)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    thumbnail(photo).frame(height: 110).clipped()
                    Text(photo.file).font(.caption).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Color.clear.frame(width: 20, height: 20)
                        Text(photo.dir).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }.padding(7)
            }
        }
    }
    private func dismissPreview() {
        model.closePreview()
        galleryFocus.restore(model.active, afterPreview: true)
    }
    private func preview(_ photo: CameraPhoto) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.previewPosition).font(.caption).lineLimit(1).truncationMode(.middle).help(model.previewPosition)
                Spacer(minLength: 4)
                Button { dismissPreview() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close preview")
            }
            CameraImageView(photo: photo, rendition: .preview, loader: images)
                .onTapGesture { previewFocusRevision += 1 }
                .id(CameraImageKey(generation: images.generation, photo: photo, rendition: .preview))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button { model.navigatePreview(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous photo")
                Spacer()
                Button("Download original") { model.requestDownload([photo.path]) }.disabled(!model.canDownload)
                Spacer()
                Button { model.navigatePreview(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next photo")
            }.controlSize(.small)
        }.padding(12).background(Color(nsColor: .windowBackgroundColor))
            .background(PreviewKeyboard(photo: photo, focusRevision: previewFocusRevision, restore: { galleryFocus.restore(model.active, afterPreview: true) }) { key in
                if key == 53 { dismissPreview() }
                else { model.navigatePreview(key == 123 ? -1 : 1) }
            }.frame(width: 0, height: 0))
            .accessibilityElement(children: .contain).accessibilityLabel("Photo preview")
    }
}
