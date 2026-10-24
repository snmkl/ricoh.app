import Foundation

/// Membership is authoritative here; the baseline distinguishes independent choices
/// from photos introduced by the current anchored range.
struct PhotoSelection {
    private(set) var selected = Set<CameraPhoto>()
    private(set) var active: CameraPhoto?
    private(set) var anchor: CameraPhoto?
    private(set) var baseline: Set<CameraPhoto>?

    mutating func origin(_ photo: CameraPhoto) {
        active = photo; anchor = photo; baseline = nil
    }
    mutating func focus(_ photo: CameraPhoto) {
        if active != photo { origin(photo) }
    }
    mutating func toggle(_ photo: CameraPhoto) {
        origin(photo)
        if !selected.insert(photo).inserted { selected.remove(photo) }
    }
    mutating func bulk(_ photos: Set<CameraPhoto>) {
        selected = photos; anchor = nil; baseline = nil
    }
    mutating func range(to endpoint: CameraPhoto, in photos: [CameraPhoto]) {
        guard let end = photos.firstIndex(of: endpoint) else { return }
        let anchorIndex = anchor.flatMap { photos.firstIndex(of: $0) }
        let start = anchorIndex ?? active.flatMap { photos.firstIndex(of: $0) } ?? end
        if baseline == nil || anchorIndex == nil { baseline = selected; anchor = photos[start] }
        // Missing identities can only arise from stale callers; never select them.
        selected = (baseline ?? []).intersection(photos).union(photos[min(start, end)...max(start, end)])
        active = endpoint
    }
    mutating func move(_ direction: GalleryDirection, in photos: [CameraPhoto], columns: Int, list: Bool) {
        guard !photos.isEmpty else { return }
        guard let active = active, let index = photos.firstIndex(of: active) else {
            anchor = nil; baseline = nil
            range(to: photos[0], in: photos)
            return
        }
        let stride = max(1, columns)
        let next: Int
        switch direction {
        case .left: next = max(0, index - 1)
        case .right: next = min(photos.count - 1, index + 1)
        case .up:
            next = list ? max(0, index - 1) : (index < stride ? index : index - stride)
        case .down:
            next = list ? min(photos.count - 1, index + 1) :
                (index / stride == (photos.count - 1) / stride ? index : min(photos.count - 1, index + stride))
        }
        guard next != index else { return }
        range(to: photos[next], in: photos)
    }
}

enum GalleryDirection {
    case left, right, up, down
    init?(keyCode: UInt16) {
        switch keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: return nil
        }
    }
}

/// The same count constructs the grid and determines its keyboard stride.
struct GalleryMetrics {
    static let padding: CGFloat = 12
    static let spacing: CGFloat = 10
    static let minimum: CGFloat = 145
    static func columns(width: CGFloat) -> Int {
        max(1, Int((max(0, width - 2 * padding) + spacing) / (minimum + spacing)))
    }
}
