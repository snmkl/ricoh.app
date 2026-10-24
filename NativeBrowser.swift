import Cocoa
import SwiftUI

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

struct BluetoothRouteIcon: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 5, y: 1)); path.addLine(to: CGPoint(x: 5, y: 17))
            path.addLine(to: CGPoint(x: 11, y: 12)); path.addLine(to: CGPoint(x: 0, y: 4))
            path.move(to: CGPoint(x: 5, y: 1)); path.addLine(to: CGPoint(x: 11, y: 6))
            path.addLine(to: CGPoint(x: 0, y: 14))
        }.stroke(lineWidth: 1.5).frame(width: 12, height: 18)
    }
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
    func restoreFocus() {
        guard let window = window, window.firstResponder === self else { return }
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
    let handle: (UInt16) -> Void
    func makeNSView(context: Context) -> PreviewKeyResponder { PreviewKeyResponder() }
    func updateNSView(_ view: PreviewKeyResponder, context: Context) { view.handle = handle; view.photo = photo; view.focusRevision = focusRevision }
    static func dismantleNSView(_ view: PreviewKeyResponder, coordinator: ()) { view.restoreFocus() }
}

@MainActor
struct NativeBrowserView: View {
    @StateObject var model: BrowserModel
    @StateObject var images: CameraImageLoader
    let showSettings: () -> Void
    @FocusState private var focusedPhoto: CameraPhoto?
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
                Button(model.selected.count == model.photos.count && !model.photos.isEmpty ? "Deselect all" : "Select all", action: model.selectAll)
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
        .onChange(of: model.preview) { photo in focusedPhoto = photo == nil ? model.active : nil }
        .accessibilityIdentifier("camera-browser")
    }
    private var header: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Group { if bluetoothTarget { BluetoothRouteIcon() } else { Image(systemName: "wifi").frame(width: 14) } }
                .foregroundStyle(.secondary).accessibilityHidden(true)
            Picker(bluetoothTarget ? "Bluetooth connection target" : "Wi-Fi connection target", selection: Binding(get: { model.target }, set: { model.selectTarget($0) })) {
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
            }.labelsHidden().pickerStyle(.menu).frame(minWidth: 80, idealWidth: 280, maxWidth: 320)
                .layoutPriority(-1).disabled(!model.targetsEnabled)
                .help((bluetoothTarget ? "Bluetooth · " : "Wi-Fi · ") + model.targetLabel)
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
                            LazyVStack(spacing: 8) { ForEach(model.photos) { photo in photoRow(photo) } }.padding(12)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                                ForEach(model.photos) { photo in photoCard(photo) }
                            }.padding(12)
                        }
                    }.accessibilityLabel("Camera photo gallery")
                        .onChange(of: focusedPhoto) { photo in if let photo = photo { proxy.scrollTo(photo) } }
                }
            }
        }
    }
    private func thumbnail(_ photo: CameraPhoto) -> some View {
        CameraImageView(photo: photo, rendition: .thumbnail, loader: images)
            .id(CameraImageKey(generation: images.generation, photo: photo, rendition: .thumbnail))
    }
    private func photoCard(_ photo: CameraPhoto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.openPreview(photo) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    thumbnail(photo).frame(height: 110).clipped()
                    Text(photo.file).font(.caption).lineLimit(1).truncationMode(.middle)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Preview " + photo.file)
                .focused($focusedPhoto, equals: photo)
            HStack {
                Toggle("Select " + photo.file, isOn: Binding(get: { model.selected.contains(photo) }, set: { _ in model.toggle(photo) }))
                    .labelsHidden().toggleStyle(.checkbox).accessibilityLabel("Select " + photo.file)
                Text(photo.dir).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
        }.padding(7).background(model.selected.contains(photo) ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.03))
            .cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(model.selected.contains(photo) ? Color.accentColor : .clear))
            .id(photo).help(photo.path)
    }
    private func photoRow(_ photo: CameraPhoto) -> some View {
        HStack(spacing: 10) {
            Toggle("Select " + photo.file, isOn: Binding(get: { model.selected.contains(photo) }, set: { _ in model.toggle(photo) }))
                .labelsHidden().toggleStyle(.checkbox).accessibilityLabel("Select " + photo.file)
            Button { model.openPreview(photo) } label: {
                HStack(spacing: 10) {
                    thumbnail(photo).frame(width: 80, height: 54)
                    VStack(alignment: .leading) { Text(photo.file).lineLimit(1); Text(photo.dir).font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Preview " + photo.file).focused($focusedPhoto, equals: photo)
        }.padding(7).background(model.selected.contains(photo) ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.03)).cornerRadius(6).id(photo)
    }
    private func preview(_ photo: CameraPhoto) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.previewPosition).font(.caption).lineLimit(1).truncationMode(.middle).help(model.previewPosition)
                Spacer(minLength: 4)
                Button { model.closePreview() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close preview")
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
            .background(PreviewKeyboard(photo: photo, focusRevision: previewFocusRevision) { key in
                if key == 53 { model.closePreview() }
                else { model.navigatePreview(key == 123 ? -1 : 1) }
            }.frame(width: 0, height: 0))
            .accessibilityElement(children: .contain).accessibilityLabel("Photo preview")
    }
}
