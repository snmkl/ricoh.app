import Foundation
import SystemConfiguration

enum RicohBLE {
    static let information = "9A5ED1C5-74CC-4C50-B5B6-66A48E7CCFF1"
    static let camera = "4B445988-CAA0-4DD3-941D-37B4F52ACA86"
    static let wlan = "F37F568F-9071-445D-A938-5441F2E82399"
    static let bluetoothControl = "0F291746-0C80-4726-87A7-3C501FD3B4B6"
    static let pairedDeviceName = "FE3A32F8-A189-42DE-A391-BC81AE4DAA76"
    static let model = "35FE6272-6AA5-44D9-88E1-F09427F51A71"
    static let firmware = "B4EB8905-7411-40A6-A367-2834C2157EA7"
    static let serial = "0D2FC4D5-5CB3-4CDE-B519-445E599957D8"
    static let power = "B58CE84C-0666-4DE9-BEC8-2D27B27B3211"
    static let mode = "1452335A-EC7F-4877-B8AB-0F72E18BB295"
    static let network = "9111CDD0-9F01-45C4-A2D4-E09E8FB0424D"
    static let ssid = "90638E5A-E77D-409D-B550-78F7E1CA5AB4"
    static let password = "0F38279C-FE9E-461B-8596-81287E8C9A81"
    static let services = [information, camera, wlan]
    static let discoveryServices = services + [bluetoothControl]
    static let optional: [String: [String]] = [information: [serial], bluetoothControl: [pairedDeviceName]]
    static let required: [String: [String]] = [information: [model, firmware],
        camera: [power, mode], wlan: [network, ssid, password]]
    static func text(_ data: Data) throws -> String {
        var bytes = data
        while bytes.last == 0 { bytes.removeLast() }
        guard let value = String(data: bytes, encoding: .utf8), !value.contains("\0") else {
            throw BluetoothFailure.invalidValue
        }
        return value
    }
    static func byte(_ data: Data, allowed: ClosedRange<UInt8>) throws -> UInt8 {
        guard data.count == 1, let value = data.first, allowed.contains(value) else {
            throw BluetoothFailure.invalidValue
        }
        return value
    }
    static func supported(_ model: String) -> Bool { ["RICOH GR III", "RICOH GR IIIx"].contains(model) }
    static func deviceNamePayload(_ name: String?) -> Data? {
        guard let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.contains("\0") else { return nil }
        return Data(name.utf8)
    }
}

enum BluetoothFailure: LocalizedError {
    case unavailable(String), unsupported, pairing, timeout, disconnected, rejected, invalidValue
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .unsupported: return "This device does not expose supported Ricoh GR III/IIIx Bluetooth control. Use camera Wi-Fi."
        case .pairing: return "Bluetooth pairing failed. Open Bluetooth pairing on the camera, enter its passkey in macOS, and retry."
        case .timeout: return "Bluetooth setup timed out. Check camera Bluetooth, On anytime, and any phone holding its connection."
        case .disconnected: return "Camera Bluetooth disconnected during setup. Check its power and try again."
        case .rejected: return "Camera rejected remote Wi-Fi activation (0x80). Turn Wi-Fi on at the camera and use the Wi-Fi route."
        case .invalidValue: return "Camera returned an unsupported Bluetooth state or invalid Wi-Fi credentials. Use camera Wi-Fi."
        }
    }
}

struct BluetoothIdentity: Equatable {
    let id: UUID
    let name: String
    let model: String
    let firmware: String
    let serial: String?
}
struct BluetoothObservation {
    let id: UUID
    let name: String
    let seen: Date
    let systemConnected: Bool
}
struct BluetoothWiFiCredentials {
    let ssid: String
    let password: String
    init(ssid: String, password: String) throws {
        let key = Array(password.utf8)
        let hexKey = key.count == 64 && key.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        guard !ssid.isEmpty, ssid.utf8.count <= 32, !ssid.contains("\0"),
              hexKey || ((8...63).contains(key.count) && key.allSatisfy { (32...126).contains($0) }) else {
            throw BluetoothFailure.invalidValue
        }
        self.ssid = ssid; self.password = password
    }
}
struct BluetoothHandoff {
    let identity: BluetoothIdentity
    let credentials: BluetoothWiFiCredentials
    let apConfirmed: Bool
}

// Transport callbacks and all orchestration are confined to the main thread.
protocol BluetoothTransport: AnyObject {
    var state: String { get }
    var observations: [BluetoothObservation] { get }
    var connectedID: UUID? { get }
    var onChange: (() -> Void)? { get set }
    func discover(explicit: Bool)
    func stopDiscovery()
    func connect(_ id: UUID, completion: @escaping (Result<Void, Error>) -> Void)
    func read(_ uuid: String, pairing: Bool, completion: @escaping (Result<Data, Error>) -> Void)
    func write(_ uuid: String, value: Data, completion: @escaping (Result<Void, Error>) -> Void)
    func disconnect(_ completion: @escaping () -> Void)
}

protocol CameraBluetoothAccess: AnyObject {
    var state: String { get }
    var observations: [BluetoothObservation] { get }
    var connectedID: UUID? { get }
    var onChange: (() -> Void)? { get set }
    func discover(explicit: Bool)
    func stopDiscovery()
    func prepare(_ id: UUID, identified: @escaping (BluetoothIdentity) -> Void,
                 progress: @escaping (String) -> Void, completion: @escaping (Result<BluetoothHandoff, Error>) -> Void)
    func refreshCredentials(_ completion: @escaping (Result<BluetoothWiFiCredentials, Error>) -> Void)
    func release(_ completion: @escaping () -> Void)
}

final class BluetoothCamera: CameraBluetoothAccess {
    private let transport: BluetoothTransport
    private let computerName: () -> String?
    private let later: (TimeInterval, @escaping () -> Void) -> Void
    private var generation = UUID()
    private var preparation: Preparation?
    var onChange: (() -> Void)?
    var state: String { transport.state }
    var observations: [BluetoothObservation] { transport.observations }
    var connectedID: UUID? { transport.connectedID }
    init(transport: BluetoothTransport = CoreBluetoothTransport(),
         computerName: @escaping () -> String? = { SCDynamicStoreCopyComputerName(nil, nil) as String? },
         later: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.transport = transport; self.computerName = computerName; self.later = later
        transport.onChange = { [weak self] in self?.onChange?() }
    }
    func discover(explicit: Bool) { transport.discover(explicit: explicit) }
    func stopDiscovery() { transport.stopDiscovery() }
    func release(_ completion: @escaping () -> Void) {
        generation = UUID(); preparation = nil
        transport.stopDiscovery(); transport.disconnect(completion)
    }
    private final class Preparation {
        let token: UUID
        let id: UUID
        let identified: (BluetoothIdentity) -> Void
        let progress: (String) -> Void
        let completion: (Result<BluetoothHandoff, Error>) -> Void
        var identity: BluetoothIdentity?
        var cached: BluetoothWiFiCredentials?
        var requestedAP = false
        var finished = false
        init(token: UUID, id: UUID, identified: @escaping (BluetoothIdentity) -> Void,
             progress: @escaping (String) -> Void, completion: @escaping (Result<BluetoothHandoff, Error>) -> Void) {
            self.token = token; self.id = id; self.identified = identified; self.progress = progress; self.completion = completion
        }
    }
    private func active(_ job: Preparation) -> Bool { generation == job.token && !job.finished }
    private func finish(_ job: Preparation, _ result: Result<BluetoothHandoff, Error>) {
        guard active(job) else { return }; job.finished = true; job.cached = nil; preparation = nil
        job.completion(result)
    }
    private func failed(_ job: Preparation, _ error: Error) {
        guard active(job) else { return }
        // A disconnect can be the camera changing radio modes; association must still prove AP readiness.
        if job.requestedAP, transport.connectedID == nil, let identity = job.identity, let cached = job.cached,
           case BluetoothFailure.disconnected = error {
            finish(job, .success(BluetoothHandoff(identity: identity, credentials: cached, apConfirmed: false)))
        } else { finish(job, .failure(error)) }
    }
    private func read(_ uuid: String, job: Preparation, pairing: Bool = false, then: @escaping (Data) throws -> Void) {
        guard active(job) else { return }
        transport.read(uuid, pairing: pairing) { [weak self] result in
            guard let self = self, self.active(job) else { return }
            do { try then(result.get()) } catch { self.failed(job, error) }
        }
    }
    private func write(_ uuid: String, job: Preparation, then: @escaping () -> Void) {
        guard active(job) else { return }
        transport.write(uuid, value: Data([1])) { [weak self] result in
            guard let self = self, self.active(job) else { return }
            switch result { case .success: then(); case .failure(let error): self.failed(job, error) }
        }
    }
    func prepare(_ id: UUID, identified: @escaping (BluetoothIdentity) -> Void,
                 progress: @escaping (String) -> Void, completion: @escaping (Result<BluetoothHandoff, Error>) -> Void) {
        generation = UUID()
        let job = Preparation(token: generation, id: id, identified: identified, progress: progress, completion: completion)
        preparation = job; transport.stopDiscovery()
        later(165) { [weak self, weak job] in
            guard let self = self, let job = job, self.active(job) else { return }
            self.failed(job, BluetoothFailure.timeout)
        }
        progress("Connecting Bluetooth (experimental)…")
        transport.connect(id) { [weak self, job] result in
            guard let self = self, self.active(job) else { return }
            switch result {
            case .failure(let error): self.failed(job, error)
            case .success:
                progress("Checking camera pairing… Complete any macOS passkey prompt.")
                self.read(RicohBLE.power, job: job, pairing: true) { [self, job] powerData in
                    let power = try RicohBLE.byte(powerData, allowed: 0...2)
                    self.later(45) { [weak self, weak job] in
                        guard let self = self, let job = job, self.active(job), !job.requestedAP else { return }
                        self.failed(job, BluetoothFailure.timeout)
                    }
                    self.read(RicohBLE.model, job: job) { data in
                        let model = try RicohBLE.text(data)
                        guard RicohBLE.supported(model) else { throw BluetoothFailure.unsupported }
                        self.read(RicohBLE.firmware, job: job) { data in
                            let firmware = try RicohBLE.text(data)
                            guard !firmware.isEmpty else { throw BluetoothFailure.invalidValue }
                            self.read(RicohBLE.serial, job: job) { serialData in
                                let serial = try RicohBLE.text(serialData)
                                let identity = BluetoothIdentity(id: id, name: self.transport.observations.first { $0.id == id }?.name ?? model,
                                                                 model: model, firmware: firmware, serial: serial.isEmpty ? nil : serial)
                                job.identity = identity; identified(identity)
                                self.read(RicohBLE.mode, job: job) { data in
                                    _ = try RicohBLE.byte(data, allowed: 0...4)
                                    self.sendComputerName(job) {
                                        if power == 1 { self.prepareAP(job) }
                                        else {
                                            progress("Preparing camera…")
                                            self.write(RicohBLE.power, job: job) { self.waitPower(job, tries: 10) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private func sendComputerName(_ job: Preparation, then: @escaping () -> Void) {
        guard active(job) else { return }
        // Read the current Computer Name each time, so renaming the Mac updates its camera label on reconnect.
        guard let payload = RicohBLE.deviceNamePayload(computerName()) else { then(); return }
        job.progress("Updating the camera's paired-device name…")
        transport.write(RicohBLE.pairedDeviceName, value: payload) { [weak self] result in
            guard let self = self, self.active(job) else { return }
            if case .failure(let error) = result {
                if self.transport.connectedID != job.id {
                    self.failed(job, error); return
                }
                switch error {
                case BluetoothFailure.pairing, BluetoothFailure.disconnected, BluetoothFailure.timeout:
                    self.failed(job, error); return
                default:
                    job.progress("Could not update the paired-device name. Continuing connection…")
                }
            }
            then()
        }
    }
    private func waitPower(_ job: Preparation, tries: Int) {
        guard active(job) else { return }
        read(RicohBLE.power, job: job) { data in
            let power = try RicohBLE.byte(data, allowed: 0...2)
            if power == 1 { self.prepareAP(job) }
            else if tries > 0 { self.later(0.5) { self.waitPower(job, tries: tries - 1) } }
            else { throw BluetoothFailure.timeout }
        }
    }
    private func prepareAP(_ job: Preparation) {
        // A pre-read is optional; empty/stale values can occur before WLAN has ever been enabled.
        refreshCredentials { [weak self, job] result in
            guard let self = self, self.active(job) else { return }
            if case .success(let value) = result { job.cached = value }
            else if case .failure(let error) = result {
                if case BluetoothFailure.invalidValue = error { /* Unconfigured WLAN may have empty credentials. */ }
                else { self.failed(job, error); return }
            }
            self.read(RicohBLE.network, job: job) { [self, job] data in
                let network = try RicohBLE.byte(data, allowed: 0...1)
                job.progress("Turning on camera Wi-Fi…")
                if network == 1 { self.finishAP(job) }
                else {
                    job.requestedAP = true
                    self.later(10) { [weak self, weak job] in
                        guard let self = self, let job = job, self.active(job) else { return }
                        self.failed(job, BluetoothFailure.timeout)
                    }
                    self.write(RicohBLE.network, job: job) { self.waitAP(job, tries: 10) }
                }
            }
        }
    }
    private func waitAP(_ job: Preparation, tries: Int) {
        read(RicohBLE.network, job: job) { data in
            if try RicohBLE.byte(data, allowed: 0...1) == 1 { self.finishAP(job) }
            else if tries > 0 { self.later(0.5) { if self.active(job) { self.waitAP(job, tries: tries - 1) } } }
            else { throw BluetoothFailure.timeout }
        }
    }
    private func finishAP(_ job: Preparation) {
        refreshCredentials { [weak self, job] result in
            guard let self = self, self.active(job), let identity = job.identity else { return }
            switch result {
            case .success(let credentials): self.finish(job, .success(BluetoothHandoff(identity: identity, credentials: credentials, apConfirmed: true)))
            case .failure(let error): self.failed(job, error)
            }
        }
    }
    func refreshCredentials(_ completion: @escaping (Result<BluetoothWiFiCredentials, Error>) -> Void) {
        let token = generation
        transport.read(RicohBLE.ssid, pairing: false) { [weak self] result in
            guard let self = self, self.generation == token else { return }
            do {
                let ssid = try RicohBLE.text(result.get())
                self.transport.read(RicohBLE.password, pairing: false) { [weak self] result in
                    guard let self = self, self.generation == token else { return }
                    completion(Result { try BluetoothWiFiCredentials(ssid: ssid, password: RicohBLE.text(result.get())) })
                }
            } catch { completion(.failure(error)) }
        }
    }
}

struct RememberedBluetoothCamera {
    var identity: BluetoothIdentity
    var identified: Date
    var connected: Date?
    var networkID: String?
}
final class BluetoothDeviceStore {
    private let defaults: UserDefaults
    private let key = "bluetooth-cameras.v1"
    private(set) var cameras: [RememberedBluetoothCamera] = []
    private(set) var preferred: UUID?
    private(set) var revisions: [UUID: Int] = [:]
    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let value = defaults.dictionary(forKey: key), value["version"] as? Int == 1 else { return }
        preferred = (value["preferred"] as? String).flatMap(UUID.init(uuidString:))
        var seen = Set<UUID>()
        for record in value["cameras"] as? [[String: Any]] ?? [] {
            guard let raw = record["id"] as? String, let id = UUID(uuidString: raw), seen.insert(id).inserted,
                  let model = record["model"] as? String, RicohBLE.supported(model), let name = record["name"] as? String,
                  let firmware = record["firmware"] as? String, let time = record["identified"] as? Double, time.isFinite else { continue }
            let success = (record["connected"] as? Double).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
            cameras.append(RememberedBluetoothCamera(identity: BluetoothIdentity(id: id, name: name, model: model,
                firmware: firmware, serial: record["serial"] as? String), identified: Date(timeIntervalSince1970: time),
                connected: success, networkID: record["network"] as? String))
        }
        if !cameras.contains(where: { $0.identity.id == preferred }) { preferred = nil }
    }
    func select(_ id: UUID?) { preferred = id; persist() }
    func remember(_ identity: BluetoothIdentity, at date: Date) {
        if let index = cameras.firstIndex(where: { $0.identity.id == identity.id }) {
            cameras[index].identity = identity; cameras[index].identified = date
        } else { cameras.append(RememberedBluetoothCamera(identity: identity, identified: date)) }
        persist()
    }
    func succeeded(_ id: UUID, network: String?, at date: Date) {
        guard let index = cameras.firstIndex(where: { $0.identity.id == id }) else { return }
        cameras[index].connected = date; cameras[index].networkID = network; persist()
    }
    func forget(_ id: UUID) {
        revisions[id, default: 0] += 1; cameras.removeAll { $0.identity.id == id }
        if preferred == id { preferred = nil }; persist()
    }
    func unlink(_ network: String) {
        for index in cameras.indices where cameras[index].networkID == network { cameras[index].networkID = nil }
        persist()
    }
    private func persist() {
        var record: [String: Any] = ["version": 1, "cameras": cameras.map { camera -> [String: Any] in
            var value: [String: Any] = ["id": camera.identity.id.uuidString, "name": camera.identity.name,
                "model": camera.identity.model, "firmware": camera.identity.firmware,
                "identified": camera.identified.timeIntervalSince1970]
            value["serial"] = camera.identity.serial; value["connected"] = camera.connected?.timeIntervalSince1970
            value["network"] = camera.networkID; return value
        }]
        record["preferred"] = preferred?.uuidString; defaults.set(record, forKey: key)
    }
}
