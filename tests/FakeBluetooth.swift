import Cocoa
import CoreWLAN
import CoreLocation
import Security
import Darwin

final class FakeBluetoothAccess: CameraBluetoothAccess {
    var state = "Bluetooth on"
    var observations: [BluetoothObservation] = []
    var connectedID: UUID?
    var onChange: (() -> Void)?
    var discoveries = 0, prepares = 0, releases = 0, credentialReads = 0
    var hold = false, holdRelease = false
    var pending: ((Result<BluetoothHandoff, Error>) -> Void)?
    var releasePending: (() -> Void)?
    var result: Result<BluetoothHandoff, Error> = .failure(BluetoothFailure.unsupported)
    func discover(explicit: Bool) { discoveries += 1 }
    func stopDiscovery() {}
    func prepare(_ id: UUID, identified: @escaping (BluetoothIdentity) -> Void,
                 progress: @escaping (String) -> Void, completion: @escaping (Result<BluetoothHandoff, Error>) -> Void) {
        prepares += 1; connectedID = id; progress("Connecting Bluetooth…"); onChange?()
        if case .success(let handoff) = result { identified(handoff.identity) }
        if hold { pending = completion } else { completion(result) }
    }
    func refreshCredentials(_ completion: @escaping (Result<BluetoothWiFiCredentials, Error>) -> Void) {
        credentialReads += 1; completion(result.map(\.credentials))
    }
    func release(_ completion: @escaping () -> Void) {
        releases += 1; connectedID = nil; onChange?()
        if holdRelease { releasePending = completion } else { completion() }
    }
}

final class FakeBLETransport: BluetoothTransport {
    var state = "Bluetooth on"
    var observations: [BluetoothObservation] = []
    var connectedID: UUID?
    var onChange: (() -> Void)?
    var calls: [String] = []
    var writes: [(String, Data)] = []
    var rejectAP = false, dropAP = false, holdPower = false
    var nameWriteError: Error?
    var heldPower: ((Result<Data, Error>) -> Void)?
    var values: [String: Data] = [RicohBLE.model: Data("RICOH GR IIIx\0".utf8),
        RicohBLE.firmware: Data("1.41\0".utf8), RicohBLE.power: Data([0]), RicohBLE.mode: Data([2]),
        RicohBLE.network: Data([0]), RicohBLE.ssid: Data("GR_TEST\0\0".utf8), RicohBLE.password: Data("test-key\0".utf8)]
    func discover(explicit: Bool) { calls.append("discover") }
    func stopDiscovery() {}
    func connect(_ id: UUID, completion: @escaping (Result<Void, Error>) -> Void) {
        connectedID = id; calls.append("connect"); completion(.success(()))
    }
    func read(_ uuid: String, pairing: Bool, completion: @escaping (Result<Data, Error>) -> Void) {
        calls.append("read:" + uuid)
        if uuid == RicohBLE.power && holdPower { heldPower = completion; return }
        if uuid == RicohBLE.serial && values[uuid] == nil { completion(.success(Data())); return }
        completion(values[uuid].map { .success($0) } ?? .failure(BluetoothFailure.unsupported))
    }
    func write(_ uuid: String, value: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        calls.append("write:" + uuid); writes.append((uuid, value))
        if uuid == RicohBLE.pairedDeviceName, let error = nameWriteError {
            if case BluetoothFailure.disconnected = error { connectedID = nil }
            completion(.failure(error)); return
        }
        if uuid == RicohBLE.network && rejectAP { completion(.failure(BluetoothFailure.rejected)); return }
        if uuid == RicohBLE.network && dropAP { connectedID = nil; completion(.failure(BluetoothFailure.disconnected)); return }
        values[uuid] = value; completion(.success(()))
    }
    func disconnect(_ completion: @escaping () -> Void) { connectedID = nil; calls.append("disconnect"); completion() }
}

func runPreparation(_ transport: FakeBLETransport, computerName: String? = "Fixture MacBook") -> Result<BluetoothHandoff, Error> {
    let camera = BluetoothCamera(transport: transport, computerName: { computerName })
    // Immediate fake responses avoid radio timing; delayed-path tests use an injected scheduler below.
    var result: Result<BluetoothHandoff, Error>?
    camera.prepare(UUID(), identified: { _ in }, progress: { _ in }) { result = $0 }
    check(result != nil, "Fake BLE preparation finishes")
    return result!
}

final class BluetoothRig {
    let prefs = testPreferences()
    let radio = FakeBluetoothAccess()
    let wifi = FakeWiFi()
    let auth = FakeAuthorization()
    let camera = FakeCamera()
    let saved = FakeCredentials()
    let own = FakeCredentials()
    let clock = TestClock()
    let id = UUID()
    var events: [ConnectionEvent] = []
    lazy var devices = BluetoothDeviceStore(defaults: prefs.defaults)
    lazy var connection = CameraConnection(bluetooth: radio, devices: devices, preferences: prefs,
        wifi: wifi, authorization: auth, credentials: own, savedCredentials: saved,
        camera: camera, health: FakeCamera(), now: { self.clock.time }, later: clock.schedule)
    init() {
        let identity = BluetoothIdentity(id: id, name: "GR_<test>", model: "RICOH GR IIIx", firmware: "1.41", serial: nil)
        radio.observations = [BluetoothObservation(id: id, name: identity.name, seen: clock.time, systemConnected: false)]
        radio.result = .success(BluetoothHandoff(identity: identity,
            credentials: try! BluetoothWiFiCredentials(ssid: cameraB.name, password: "ble-fixture-key"), apConfirmed: true))
        connection.onEvent = { self.events.append($0) }
    }
    func start() { connection.connect(id: "bluetooth-attempt", target: "bt:" + id.uuidString) }
    func wait(_ outcome: String = "completed") {
        waitFor("Bluetooth coordinator terminal") { self.events.contains { terminalPhases.contains($0.phase.rawValue) } }
        check(events.last?.phase.rawValue == outcome, "Bluetooth connection outcome \(outcome)")
    }
}
