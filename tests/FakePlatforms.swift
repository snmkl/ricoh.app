import Cocoa
import CoreWLAN
import CoreLocation
import Security
import Darwin

final class FakeAuthorization: WiFiAuthorization {
    var allowed = true
    var requests = 0
    var hold = false
    var pending: [(Bool) -> Void] = []
    func request(_ completion: @escaping (Bool) -> Void) {
        requests += 1
        if hold { pending.append(completion) } else { completion(allowed) }
    }
}
final class FakeWiFi: WiFiAccess {
    var networks = [cameraA, cameraB]
    var joined: CameraNetwork? = cameraA
    var readyValue = true
    var scanError = false
    var joinError = false
    var joins: [String] = []
    var joinPasswords: [String?] = []
    var rejectedPasswords = Set<String>()
    var scans = 0
    var readinessChecks = 0
    var onCurrent: (() -> CameraNetwork?)?
    var onJoin: (() -> Void)?
    var enabledValue = true
    func enabled() -> Bool { enabledValue }
    func current() -> CameraNetwork? {
        if let onCurrent = onCurrent { return onCurrent() }
        return joined
    }
    func scan() throws -> [CameraNetwork] {
        scans += 1
        if scanError { throw appError("Discovery unavailable") }
        return networks
    }
    func join(_ network: CameraNetwork, password: String?) throws {
        onJoin?()
        joins.append(network.id)
        joinPasswords.append(password)
        if joinError || password.map({ rejectedPasswords.contains($0) }) == true { throw appError("Could not join Wi-Fi") }
        joined = network
    }
    func ready(on network: CameraNetwork?) -> Bool { readinessChecks += 1; return readyValue }
}
final class FakeCredentials: CameraCredentials, SavedWiFiCredentials {
    var values: [String: String] = [:]
    var failRead = false, failWrite = false, failDelete = false
    var cancelRead = false
    var reads: [String] = []
    var writes: [String] = []
    var removals: [String] = []
    func password(for id: String) throws -> String? {
        reads.append(id)
        if cancelRead { throw SavedWiFiCredentialError.cancelled }
        if failRead { throw appError("Keychain read failed") }; return values[id]
    }
    func save(_ password: String, for id: String) throws {
        writes.append(id)
        if failWrite { throw appError("Keychain write failed") }; values[id] = password
    }
    func remove(_ id: String) throws {
        removals.append(id)
        if failDelete { throw appError("Keychain delete failed") }; values[id] = nil
    }
}
final class FakeCamera: CameraVerification {
    var identityMatches = true
    func identify(_ identity: BluetoothIdentity, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(identityMatches ? .success(()) : .failure(appError("Camera identity mismatch")))
    }
    var result: Result<[CameraPhoto], Error> = .success([])
    var pending: [(Result<[CameraPhoto], Error>) -> Void] = []
    var hold = false
    var calls = 0
    var onVerify: (() -> Void)?
    func verify(_ completion: @escaping (Result<[CameraPhoto], Error>) -> Void) {
        calls += 1; onVerify?()
        if hold { pending.append(completion) } else { completion(result) }
    }
    func cancel() {}
}
final class TestClock {
    var time = Date(timeIntervalSince1970: 100)
    var work: [(Date, () -> Void)] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) { work.append((time.addingTimeInterval(delay), action)) }
    func advance(_ delay: TimeInterval) {
        let end = time.addingTimeInterval(delay)
        while let next = work.indices.filter({ work[$0].0 <= end }).min(by: { work[$0].0 < work[$1].0 }) {
            let entry = work.remove(at: next); time = entry.0; entry.1()
        }
        time = end
    }
}
final class ConnectionRig {
    let prefs = testPreferences()
    let wifi = FakeWiFi()
    let auth = FakeAuthorization()
    let credentials = FakeCredentials()
    let savedCredentials = FakeCredentials()
    let camera = FakeCamera()
    let health = FakeCamera()
    let clock = TestClock()
    lazy var connection = CameraConnection(bluetooth: FakeBluetoothAccess(), preferences: prefs, wifi: wifi, authorization: auth, credentials: credentials,
                                           savedCredentials: savedCredentials, camera: camera, health: health,
                                           now: { self.clock.time }, later: clock.schedule)
    var events: [ConnectionEvent] = []
    init() {
        prefs.remember(cameraA, at: Date(timeIntervalSince1970: 1))
        prefs.remember(cameraB, at: Date(timeIntervalSince1970: 2))
        connection.onEvent = { self.events.append($0) }
        connection.passwordPrompt = { _, done in done(("fixture-secret", true)) }
    }
    func start(_ id: String = "attempt", target: String? = cameraB.id) { connection.connect(id: id, target: target) }
    func wait(_ phase: String = "completed") {
        waitFor("connection outcome") { self.events.contains { terminalPhases.contains($0.phase.rawValue) } }
        check(events.last?.phase.rawValue == phase, "Expected connection \(phase), got \(String(describing: events.last))")
    }
}
