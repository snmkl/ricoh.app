import Foundation

// Exact identities are kept separate from display labels and URL encoding.
enum ConnectionTarget: Hashable {
    case currentWiFi
    case network(String)
    case bluetooth(UUID)

    init(rawValue: String) {
        if rawValue.hasPrefix("bt:"), let id = UUID(uuidString: String(rawValue.dropFirst(3))) {
            self = .bluetooth(id)
        } else { self = rawValue.isEmpty ? .currentWiFi : .network(rawValue) }
    }
    var rawValue: String {
        switch self {
        case .currentWiFi: return ""
        case .network(let id): return id
        case .bluetooth(let id): return "bt:" + id.uuidString
        }
    }
}

enum ConnectionPhase: String {
    case preparing, credentials, joining, waiting, bluetooth, camera, draining
    case completed, failed, cancelled, disconnected, remembered
}
struct ConnectionEvent {
    let id: String
    let phase: ConnectionPhase
    let message: String
    var photos: [CameraPhoto] = []
    var warning = ""
    var finishing = false
}

enum ConnectionLifecycle: Equatable {
    case idle, connecting(String), draining(String, finishing: Bool), connected(String)
    var busy: Bool {
        switch self { case .connecting, .draining: return true; default: return false }
    }
    var primaryLabel: String {
        switch self {
        case .idle: return "CONNECT"
        case .connecting: return "CANCEL"
        case .draining(_, let finishing): return finishing ? "FINISHING…" : "CANCELLING…"
        case .connected: return "DISCONNECT"
        }
    }
    var draining: Bool { if case .draining = self { return true }; return false }
}

struct NetworkSnapshot: Identifiable {
    let network: CameraNetwork
    let lastConnected: Date
    let forgetting: Bool
    var id: String { network.id }
}
struct BluetoothSnapshot: Identifiable {
    let id: UUID
    let model: String
    let name: String
    let status: String
    let remembered: Bool
    let protected: Bool
    let firmware: String
}
struct SettingsSnapshot {
    var folder = ""
    var format: ExportFormat = .zip
    var networks: [NetworkSnapshot] = []
    var available = Set<String>()
    var current: CameraNetwork?
    var wifiReady: Bool?
    var notice = ""
    var discoveryAllowed = false
    var cameras: [BluetoothSnapshot] = []
    var bluetoothState = ""
    var bluetoothName = ""
    var bluetoothStatus = ""
    var preferredTarget: ConnectionTarget = .currentWiFi
    var selectionRevision = 0
    var lifecycle: ConnectionLifecycle = .idle
    var manualRecovery = false
    var controlsDisabled = false
}

enum DownloadPhase: String {
    case preparing, downloading, archiving, saving, completed, failed, cancelled
    var terminal: Bool { self == .completed || self == .failed || self == .cancelled }
    var label: String {
        switch self {
        case .preparing: return "Preparing download folder…"
        case .downloading: return "Downloading…"
        case .archiving: return "Creating ZIP…"
        case .saving: return "Saving…"
        case .completed: return "Saved"
        case .failed: return "Download failed"
        case .cancelled: return "Cancelled"
        }
    }
}
struct DownloadRequest {
    let id: String
    let files: [String]
}
struct DownloadEvent {
    let id: String
    let phase: DownloadPhase
    let completed: Int
    let total: Int
    let filename: String
    var fraction: Double?
    var message: String?
}
