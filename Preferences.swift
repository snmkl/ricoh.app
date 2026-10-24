import Foundation

func appError(_ message: String) -> Error {
    NSError(domain: "GRBrowser", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

struct CameraNetwork: Equatable {
    let id: String
    let name: String
    let secured: Bool
    init(name: String, data: Data? = nil, secured: Bool = true) {
        self.name = name
        self.id = (data ?? Data(name.utf8)).base64EncodedString()
        self.secured = secured
    }
}

struct KnownCameraNetwork {
    let network: CameraNetwork
    let lastConnected: Date
}

enum ExportFormat: String { case zip, separate }

// Read and changed on the main thread; download operations receive immutable snapshots.
final class AppPreferences {
    let defaults: UserDefaults
    private let key = "settings.v1"
    private(set) var format: ExportFormat = .zip
    private(set) var networks: [KnownCameraNetwork] = []
    private var folderBookmark: Data?
    private(set) var revisions: [String: Int] = [:]
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let record = defaults.dictionary(forKey: key), record["version"] as? Int == 1 else { return }
        format = ExportFormat(rawValue: record["format"] as? String ?? "") ?? .zip
        folderBookmark = record["folder"] as? Data
        var seen = Set<String>()
        for entry in record["networks"] as? [[String: Any]] ?? [] {
            guard let id = entry["id"] as? String, let data = Data(base64Encoded: id),
                  !data.isEmpty, data.count <= 32, seen.insert(id).inserted,
                  let name = entry["name"] as? String, !name.isEmpty,
                  let time = entry["lastConnected"] as? Double, time.isFinite else { continue }
            networks.append(KnownCameraNetwork(network: CameraNetwork(name: name, data: data),
                                                lastConnected: Date(timeIntervalSince1970: time)))
        }
        networks.sort { $0.lastConnected > $1.lastConnected }
    }

    func folder() -> URL? {
        guard let bookmark = folderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            folderBookmark = refreshed
            persist(notify: false)
        }
        return url
    }

    static func usableFolder(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue && FileManager.default.isWritableFile(atPath: url.path)
    }

    func setFolder(_ url: URL) throws {
        guard Self.usableFolder(url) else { throw appError("Choose an available, writable folder.") }
        folderBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        persist()
    }

    func setFormat(_ value: ExportFormat) { format = value; persist() }

    func remember(_ network: CameraNetwork, at date: Date) {
        networks.removeAll { $0.network.id == network.id }
        networks.insert(KnownCameraNetwork(network: network, lastConnected: date), at: 0)
        persist()
    }

    func invalidateHistory(for id: String) { revisions[id, default: 0] += 1 }
    func forget(_ id: String) { networks.removeAll { $0.network.id == id }; persist() }

    private func persist(notify: Bool = true) {
        var record: [String: Any] = ["version": 1, "format": format.rawValue,
            "networks": networks.map { ["id": $0.network.id, "name": $0.network.name,
                                        "lastConnected": $0.lastConnected.timeIntervalSince1970] }]
        record["folder"] = folderBookmark
        defaults.set(record, forKey: key)
        if notify { onChange?() }
    }
}
