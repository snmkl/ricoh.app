import Cocoa
import CoreWLAN
import CoreLocation
import Security

protocol WiFiAccess {
    func enabled() -> Bool
    func current() -> CameraNetwork?
    func scan() throws -> [CameraNetwork]
    func join(_ network: CameraNetwork, password: String?) throws
    func ready(on network: CameraNetwork?) -> Bool
}

extension WiFiAccess { func enabled() -> Bool { true } }

final class MacWiFi: WiFiAccess {
    func enabled() -> Bool { interface()?.powerOn() == true }
    private var scanned: [String: CWNetwork] = [:]
    private func interface() -> CWInterface? { CWWiFiClient.shared().interface() }
    func current() -> CameraNetwork? {
        guard let interface = interface(), interface.powerOn() else { return nil }
        return Self.network(name: interface.ssid(), data: interface.ssidData(), secured: interface.security() != .none)
    }
    static func network(name: String?, data: Data?, secured: Bool) -> CameraNetwork? {
        // CoreWLAN can expose one representation before the other after association/authorization.
        guard let bytes = data ?? name.map({ Data($0.utf8) }), !bytes.isEmpty,
              let display = name ?? String(data: bytes, encoding: .utf8), !display.isEmpty else { return nil }
        return CameraNetwork(name: display, data: bytes, secured: secured)
    }
    func scan() throws -> [CameraNetwork] {
        guard let interface = interface(), interface.powerOn() else { throw appError("Wi-Fi is off or unavailable.") }
        scanned = [:]
        var found: [CameraNetwork] = []
        for network in try interface.scanForNetworks(withSSID: nil) {
            guard let value = Self.network(name: network.ssid, data: network.ssidData,
                                          secured: !network.supportsSecurity(.none)) else { continue }
            if scanned[value.id] == nil { found.append(value) }
            scanned[value.id] = network
        }
        return found
    }
    func join(_ network: CameraNetwork, password: String?) throws {
        guard let interface = interface(), let target = scanned[network.id] else {
            throw appError("The selected network is no longer nearby.")
        }
        do { try interface.associate(to: target, password: password) }
        catch { throw appError("Could not join the selected Wi-Fi. Check its password and try again.") }
    }
    func ready(on network: CameraNetwork?) -> Bool {
        guard let interface = interface(), interface.powerOn(), let name = interface.interfaceName else { return false }
        if let network = network, current()?.id != network.id { return false }
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return false }
        defer { freeifaddrs(addresses) }
        var address = addresses
        while let item = address {
            defer { address = item.pointee.ifa_next }
            guard String(cString: item.pointee.ifa_name) == name,
                  let socket = item.pointee.ifa_addr, socket.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ip = UnsafeRawPointer(socket).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            if ip != 0 { return true }
        }
        return false
    }
}

protocol WiFiAuthorization: AnyObject {
    var allowed: Bool { get }
    func request(_ completion: @escaping (Bool) -> Void)
}

final class MacWiFiAuthorization: NSObject, WiFiAuthorization, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var callbacks: [(Bool) -> Void] = []
    override init() { super.init(); manager.delegate = self }
    var allowed: Bool {
        CLLocationManager.locationServicesEnabled() &&
            manager.authorizationStatus == .authorizedAlways
    }
    func request(_ completion: @escaping (Bool) -> Void) {
        guard manager.authorizationStatus == .notDetermined, CLLocationManager.locationServicesEnabled() else {
            completion(allowed); return
        }
        callbacks.append(completion)
        guard callbacks.count == 1 else { return }
        manager.requestWhenInUseAuthorization()
        // An unanswered permission dialog must not indefinitely block manual camera access.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.respond() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { respond() }
    }
    private func respond() {
        let pending = callbacks; callbacks = []
        pending.forEach { $0(allowed) }
    }
}

protocol CameraCredentials {
    func password(for id: String) throws -> String?
    func save(_ password: String, for id: String) throws
    func remove(_ id: String) throws
}

// Read-only access to macOS-owned Wi-Fi credentials; writes/deletion stay app-owned.
protocol SavedWiFiCredentials {
    func password(for id: String) throws -> String?
}

enum SavedWiFiCredentialError: Error { case cancelled }

final class MacWiFiCredentials: SavedWiFiCredentials {
    typealias Lookup = (CWKeychainDomain, Data) -> (OSStatus, String?)
    private let lookup: Lookup
    init(lookup: @escaping Lookup = MacWiFiCredentials.lookup) { self.lookup = lookup }

    private static func lookup(_ domain: CWKeychainDomain, _ ssid: Data) -> (OSStatus, String?) {
        var password: NSString?
        let status = CWKeychainFindWiFiPassword(domain, ssid, &password)
        return (status, password as String?)
    }

    func password(for id: String) throws -> String? {
        guard let ssid = Data(base64Encoded: id), !ssid.isEmpty, ssid.count <= 32 else {
            throw appError("The selected Wi-Fi identity is invalid.")
        }
        for domain in [CWKeychainDomain.user, .system] {
            let (status, password) = lookup(domain, ssid)
            if status == errSecSuccess, let password = password, !password.isEmpty { return password }
            if status == errSecUserCanceled { throw SavedWiFiCredentialError.cancelled }
            // No saved item: try the other domain. Denied/locked/unavailable access:
            // fall back to app-owned credentials without another macOS access request.
            if status != errSecItemNotFound && status != errSecSuccess { return nil }
        }
        return nil
    }
}

final class KeychainCameraCredentials: CameraCredentials {
    private let service: String
    init(service: String = "local.GRBrowser.camera-wifi") { self.service = service }
    private func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw appError("Camera password Keychain access failed (\(status)).") }
    }
    func password(for id: String) throws -> String? {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw appError("The stored camera password cannot be read.")
        }
        return value
    }
    func save(_ password: String, for id: String) throws {
        let attributes = [kSecValueData as String: Data(password.utf8)]
        let status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = Data(password.utf8)
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove(_ id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}
