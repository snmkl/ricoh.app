import Foundation

// Main-thread lifecycle; blocking Wi-Fi and Keychain calls run on the serial worker.
final class CameraConnection {
    let bluetooth: CameraBluetoothAccess
    let devices: BluetoothDeviceStore
    var selectedBluetooth: UUID?
    var bluetoothLabel = ""
    var releasedBluetooth: UUID?
    var manualRecovery = false
    var selectionRevision = 0
    let preferences: AppPreferences
    let wifi: WiFiAccess
    let authorization: WiFiAuthorization
    let credentials: CameraCredentials
    let savedCredentials: SavedWiFiCredentials
    let camera: CameraVerification
    let health: CameraVerification
    let worker = DispatchQueue(label: "GRBrowser.wifi", qos: .userInitiated)
    let now: () -> Date
    let later: (TimeInterval, @escaping () -> Void) -> Void
    let timeout: TimeInterval
    var attempt: Attempt?
    var session: Session?
    lazy var discovery: CameraDiscovery = {
        let value = CameraDiscovery(wifi: wifi, authorization: authorization, bluetooth: bluetooth, worker: worker, now: now)
        value.canApply = { [weak self] in self?.isConnecting == false }
        value.canScan = { [weak self] in self?.canConnect() == true }
        value.onChange = { [weak self] notice in
            guard let self = self else { return }
            if let notice = notice { self.notice = notice }
            self.onChange?()
        }
        return value
    }()
    lazy var healthMonitor = SessionHealthMonitor(wifi: wifi, camera: health, worker: worker)
    var scanGeneration: Int { get { discovery.generation } set { discovery.generation = newValue } }
    var nearby: [CameraNetwork] { get { discovery.nearby } set { discovery.nearby = newValue } }
    var currentNetwork: CameraNetwork? { get { discovery.current } set { discovery.current = newValue } }
    var wifiReady: Bool? { get { discovery.ready } set { discovery.ready = newValue } }
    var forgetting = Set<String>()
    var currentID: String? { currentNetwork?.id }
    private(set) var notice = "Enable Wi-Fi discovery to remember and reconnect to camera networks."
    var onChange: (() -> Void)?
    var onEvent: ((ConnectionEvent) -> Void)?
    private(set) var lastEvent: ConnectionEvent?
    func publish(_ event: ConnectionEvent) { lastEvent = event; onEvent?(event) }
    var canConnect: () -> Bool = { true }
    var passwordPrompt: (String, @escaping ((String, Bool)?) -> Void) -> Void = { _, done in done(nil) }
    var isConnecting: Bool { attempt != nil }
    var isConnected: Bool { session != nil }

    // The app timer also discovers remembered networks that appear after the initial scan.
    // Permission requests remain explicit; polling never prompts or switches Wi-Fi.
    func poll(discover: Bool = true) {
        checkConnection()
        pollBluetooth(discover: discover)
        if discover { refreshCurrentNetwork() }
        if discover, !preferences.networks.isEmpty, authorization.allowed, now() >= discovery.nextScan { refresh() }
    }

    // Reading the current interface does not scan or change Wi-Fi and remains safe during downloads.
    func refreshCurrentNetwork() { discovery.refreshCurrent() }
    @discardableResult func setCurrent(_ network: CameraNetwork?, ready: Bool) -> Bool {
        discovery.setCurrent(network, ready: ready)
    }

    final class Session {
        let id: String
        let revisions: [String: Int]
        let photoCount: Int
        let bluetoothID: UUID?
        var network: CameraNetwork?
        init(job: Attempt, photoCount: Int) {
            id = job.id; revisions = job.revisions; network = job.initial; self.photoCount = photoCount; bluetoothID = job.bluetoothID
        }
    }

    final class Attempt {
        let id: String
        let cancellation = ConnectionCancellation()
        var target: String?
        var bluetoothID: UUID?
        var bluetoothRevision = 0
        var bluetoothIdentity: BluetoothIdentity?
        var bluetoothCredentials: BluetoothWiFiCredentials?
        var credentialRefreshed = false
        var deadline: Date?
        var terminal: ConnectionPhase?
        var propsVerified = false
        let revisions: [String: Int]
        var initial: CameraNetwork?
        var pendingPassword: String?
        var triedPasswords = Set<String>()
        var verified = false
        var lastFailure: Error?
        var waitingForNetwork = false
        init(id: String, target: String?, revisions: [String: Int]) {
            self.id = id; self.target = target; self.revisions = revisions
        }
    }

    init(bluetooth: CameraBluetoothAccess = BluetoothCamera(), devices: BluetoothDeviceStore? = nil,
         preferences: AppPreferences, wifi: WiFiAccess = MacWiFi(),
         authorization: WiFiAuthorization = MacWiFiAuthorization(),
         credentials: CameraCredentials = KeychainCameraCredentials(),
         savedCredentials: SavedWiFiCredentials = MacWiFiCredentials(),
         camera: CameraVerification = HTTPCameraVerification(),
         health: CameraVerification = HTTPCameraVerification(), timeout: TimeInterval = 15,
         now: @escaping () -> Date = Date.init,
         later: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.bluetooth = bluetooth; self.devices = devices ?? BluetoothDeviceStore(defaults: preferences.defaults)
        self.selectedBluetooth = self.devices.preferred
        self.preferences = preferences; self.wifi = wifi; self.authorization = authorization
        self.credentials = credentials; self.savedCredentials = savedCredentials
        self.camera = camera; self.health = health; self.timeout = timeout
        self.now = now; self.later = later
        bluetooth.onChange = { [weak self] in self?.onChange?() }
    }

    // Poll local Wi-Fi and the camera, including when SSID access is denied. No internet is required.
    func checkConnection() {
        guard let connected = session, !isConnecting, !healthMonitor.isChecking else { return }
        healthMonitor.check(expected: connected.network, allowed: authorization.allowed, observed: { network, ready in
            guard self.session === connected else { return }
            if self.setCurrent(network, ready: ready) { self.onChange?() }
        }, completion: { result in
            guard self.session === connected else { return }
            switch result {
            case .failure: self.disconnected(connected)
            case .success(let observation):
                if observation.learnedIdentity, let network = observation.initial, observation.final?.id == network.id {
                    connected.network = network
                    if self.preferences.revisions[network.id, default: 0] == connected.revisions[network.id, default: 0] {
                        self.remember(network); self.notice = ""; self.onChange?()
                        self.publish(ConnectionEvent(id: connected.id, phase: .remembered, message: "\(connected.photoCount) photos"))
                    }
                }
            }
        })
    }

    func disconnected(_ connected: Session) {
        guard session === connected else { return }
        session = nil; healthMonitor.cancel()
        scanGeneration += 1
        nearby = []
        onChange?()
        publish(ConnectionEvent(id: connected.id, phase: .disconnected, message: "Camera disconnected. Check Wi-Fi and connect again."))
    }

    func remember(_ network: CameraNetwork) {
        setCurrent(network, ready: true)
        if !nearby.contains(where: { $0.id == network.id }) { nearby.append(network) }
        preferences.remember(network, at: now())
    }

    func refresh(requestAuthorization: Bool = false) { discovery.refresh(requestAuthorization: requestAuthorization) }

    func connect(id: String, target: String?) {
        precondition(Thread.isMainThread)
        guard !isConnecting, canConnect(), !id.isEmpty else { return }
        session = nil; healthMonitor.cancel()
        scanGeneration += 1
        let bluetoothID = target.flatMap { $0.hasPrefix("bt:") ? UUID(uuidString: String($0.dropFirst(3))) : nil }
        let job = Attempt(id: id, target: bluetoothID == nil ? target : nil, revisions: preferences.revisions)
        job.bluetoothID = bluetoothID
        job.bluetoothRevision = bluetoothID.map { devices.revisions[$0, default: 0] } ?? 0
        attempt = job; manualRecovery = false
        if let bluetoothID = bluetoothID {
            beginBluetooth(job, id: bluetoothID); return
        }
        if let target = target, !preferences.networks.contains(where: { $0.network.id == target }) {
            finish(job, error: appError("That camera network was forgotten.")); return
        }
        event(job, phase: .preparing, message: "Preparing connection…")
        authorization.request { allowed in
            guard self.isLive(job) else { return }
            self.begin(job, allowed: allowed)
        }
    }

    func begin(_ job: Attempt, allowed: Bool) {
        notice = allowed ? "" : "Wi-Fi names need Location Services access. Current Wi-Fi connection still works."
        if !allowed { nearby = []; currentNetwork = nil }
        onChange?()
        worker.async {
            let initial = allowed ? self.wifi.current() : nil
            let result = Result { () -> CameraNetwork? in
                guard let target = job.target else { return nil }
                guard allowed else { throw appError("Allow Location Services to reconnect, or choose Current Wi-Fi.") }
                guard let network = try self.wifi.scan().first(where: { $0.id == target }) else {
                    throw appError("The selected camera Wi-Fi is no longer nearby.")
                }
                return network
            }
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                job.initial = initial
                if let initial = initial { self.setCurrent(initial, ready: true); self.onChange?() }
                switch result {
                case .failure(let error): self.finish(job, error: error)
                case .success(let network):
                    if let network = network, initial?.id != network.id { self.obtainPassword(job, network: network) }
                    else { self.startVerification(job, network: network ?? initial, waitForNetwork: false) }
                }
            }
        }
    }

    enum CredentialSource { case macOS, app, manual }

    func obtainPassword(_ job: Attempt, network: CameraNetwork, source: CredentialSource = .macOS) {
        guard network.secured else { join(job, network: network, password: nil); return }
        guard source != .manual else {
            event(job, phase: .credentials, message: job.lastFailure == nil ? "Waiting for Wi-Fi password…"
                : "Saved password could not connect. Enter the camera Wi-Fi password…")
            passwordPrompt(network.name) { answer in
                guard self.isLive(job) else { return }
                guard let (password, remember) = answer else {
                    self.finish(job, phase: .cancelled, message: "Connection cancelled"); return
                }
                job.pendingPassword = remember ? password : nil
                self.join(job, network: network, password: password)
            }
            return
        }
        event(job, phase: .credentials, message: source == .macOS
            ? "Checking saved macOS Wi-Fi password. Keychain access may need approval…"
            : "Checking GRBrowser's saved Wi-Fi password…")
        let next: CredentialSource = source == .macOS ? .app : .manual
        worker.async {
            let result = Result { try source == .macOS ? self.savedCredentials.password(for: network.id)
                                                     : self.credentials.password(for: network.id) }
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                switch result {
                case .failure(SavedWiFiCredentialError.cancelled):
                    self.finish(job, phase: .cancelled, message: "Keychain access cancelled")
                case .failure(let error): self.finish(job, error: error)
                case .success(let password?) where job.triedPasswords.insert(password).inserted:
                    self.join(job, network: network, password: password) {
                        self.obtainPassword(job, network: network, source: next)
                    }
                case .success: self.obtainPassword(job, network: network, source: next)
                }
            }
        }
    }

    func join(_ job: Attempt, network: CameraNetwork, password: String?, fallback: (() -> Void)? = nil) {
        event(job, phase: .joining, message: "Joining \(network.name)…")
        worker.async {
            guard !job.cancellation.isCancelled else { return }
            let result = Result { try self.wifi.join(network, password: password) }
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                switch result {
                case .failure(let error):
                    if let fallback = fallback { job.lastFailure = error; fallback() }
                    else { self.finish(job, error: error) }
                case .success:
                    job.lastFailure = nil
                    job.initial = network
                    self.startVerification(job, network: network, waitForNetwork: true)
                }
            }
        }
    }

    func startVerification(_ job: Attempt, network: CameraNetwork?, waitForNetwork: Bool) {
        // User prompts are outside this bounded network/camera readiness interval.
        let deadline = job.deadline ?? now().addingTimeInterval(timeout)
        later(timeout) {
            if self.isLive(job) && !job.verified {
                let fallback = job.waitingForNetwork ? "Wi-Fi joined but its local network did not become ready."
                    : "Camera connection timed out. Check camera Wi-Fi and try again."
                self.finish(job, error: job.lastFailure ?? appError(fallback))
            }
        }
        job.waitingForNetwork = waitForNetwork
        func checkReadiness() {
            guard self.isLive(job) else { return }
            if !waitForNetwork { self.verify(job, deadline: deadline); return }
            self.event(job, phase: .waiting, message: "Waiting for camera Wi-Fi…")
            self.worker.async {
                let ready = self.wifi.ready(on: network)
                DispatchQueue.main.async {
                    guard self.isLive(job) else { return }
                    if ready { self.verify(job, deadline: deadline) }
                    else if self.now() < deadline { self.later(0.25, checkReadiness) }
                    else { self.finish(job, error: appError("Wi-Fi did not become ready.")) }
                }
            }
        }
        checkReadiness()
    }

    func verify(_ job: Attempt, deadline: Date) {
        job.waitingForNetwork = false
        event(job, phase: .camera, message: "Connecting to camera…")
        camera.verify { result in
            guard self.isLive(job) else { return }
            switch result {
            case .failure(let error):
                job.lastFailure = error
                if self.now() < deadline { self.later(0.75) { if self.isLive(job) { self.verify(job, deadline: deadline) } } }
                else { self.finish(job, error: error) }
            case .success(let photos):
                let allowed = self.authorization.allowed
                self.worker.async {
                    let final = allowed ? self.wifi.current() : nil
                    DispatchQueue.main.async {
                        guard self.isLive(job) else { return }
                        guard job.target == nil || final?.id == job.target else {
                            self.finish(job, error: appError("Wi-Fi changed before camera verification finished.")); return
                        }
                        if job.initial == nil, let final = final, self.now() < deadline {
                            job.initial = final
                            self.verify(job, deadline: deadline)
                            return
                        }
                        if let initial = job.initial, let final = final, initial.id != final.id {
                            self.finish(job, error: appError("Wi-Fi changed before camera verification finished.")); return
                        }
                        if let identity = job.bluetoothIdentity, !job.propsVerified {
                            self.camera.identify(identity) { result in
                                guard self.isLive(job) else { return }
                                switch result {
                                case .failure(let error): self.finish(job, error: error)
                                case .success: job.propsVerified = true; self.verify(job, deadline: deadline)
                                }
                            }
                            return
                        }
                        job.verified = true
                        let stable = final != nil && final?.id == job.initial?.id
                        let forgotten = final.map { self.preferences.revisions[$0.id, default: 0] != job.revisions[$0.id, default: 0] } ?? false
                        if stable, !forgotten, let network = final {
                            self.remember(network)
                        }
                        if !stable { job.initial = nil }
                        if stable, !forgotten, let password = job.pendingPassword, let final = final {
                            self.worker.async {
                                guard !job.cancellation.isCancelled else { return }
                                let result = Result { try self.credentials.save(password, for: final.id) }
                                DispatchQueue.main.async {
                                    guard self.isLive(job) else { return }
                                    // Forget can run while a credential write is queued; serialize deletion after it.
                                    if case .failure(let error) = result { self.complete(job, photos: photos, warning: error.localizedDescription) }
                                    else { self.complete(job, photos: photos) }
                                }
                            }
                        } else { self.complete(job, photos: photos) }
                    }
                }
            }
        }
    }

    func complete(_ job: Attempt, photos: [CameraPhoto], warning: String? = nil) {
        let identityWarning = job.initial == nil ? (authorization.allowed
            ? "Wi-Fi name unavailable; network not remembered yet."
            : "Network not remembered. Allow GRBrowser in System Settings → Privacy & Security → Location Services.") : nil
        if let identityWarning = identityWarning { notice = identityWarning }
        let warning = [warning, identityWarning].compactMap { $0 }.joined(separator: " ")
        finish(job, phase: .completed, message: "\(photos.count) photos", photos: photos, warning: warning)
        onChange?()
    }

    func forget(_ id: String) {
        guard preferences.networks.contains(where: { $0.network.id == id }), forgetting.insert(id).inserted else { return }
        preferences.invalidateHistory(for: id)
        onChange?()
        worker.async {
            let result = Result { try self.credentials.remove(id) }
            DispatchQueue.main.async {
                self.forgetting.remove(id)
                switch result {
                case .success: self.preferences.forget(id); self.devices.unlink(id)
                case .failure(let error): self.notice = error.localizedDescription
                }
                self.onChange?()
            }
        }
    }

    var lifecycle: ConnectionLifecycle {
        if let attempt = attempt {
            return attempt.terminal.map { .draining(attempt.id, finishing: $0 == .completed) }
                ?? .connecting(attempt.id)
        }
        return session.map { .connected($0.id) } ?? .idle
    }
    func connect(id: String, target: ConnectionTarget) {
        connect(id: id, target: target == .currentWiFi ? nil : target.rawValue)
    }
    @discardableResult func selectTarget(_ target: ConnectionTarget) -> Bool { selectTarget(target.rawValue) }
    func settingsSnapshot() -> SettingsSnapshot {
        let bluetooth = bluetoothSnapshot()
        return SettingsSnapshot(folder: preferences.folder()?.path ?? "", format: preferences.format,
            networks: preferences.networks.map { NetworkSnapshot(network: $0.network,
                lastConnected: $0.lastConnected, forgetting: forgetting.contains($0.network.id)) },
            available: Set(nearby.map(\.id)), current: currentNetwork, wifiReady: wifiReady,
            notice: notice, discoveryAllowed: authorization.allowed, cameras: bluetooth.rows,
            bluetoothState: self.bluetooth.state, bluetoothName: bluetooth.name, bluetoothStatus: bluetooth.status,
            preferredTarget: selectedBluetooth.map { .bluetooth($0) } ?? .currentWiFi,
            selectionRevision: selectionRevision, lifecycle: lifecycle, manualRecovery: manualRecovery,
            controlsDisabled: isConnecting || isConnected || !canConnect())
    }

    func event(_ job: Attempt, phase: ConnectionPhase, message: String) {
        guard isLive(job) else { return }
        publish(ConnectionEvent(id: job.id, phase: phase, message: message))
    }
    func finish(_ job: Attempt, error: Error) { finish(job, phase: .failed, message: error.localizedDescription) }
    func finish(_ job: Attempt, phase: ConnectionPhase, message: String, photos: [CameraPhoto] = [], warning: String = "") {
        guard isLive(job) else { return }
        job.terminal = phase; camera.cancel()
        if phase != .completed { job.cancellation.cancel() }
        job.pendingPassword = nil; job.triedPasswords.removeAll(); job.bluetoothCredentials = nil
        if phase != .completed, job.bluetoothID != nil { manualRecovery = true }
        publish(ConnectionEvent(id: job.id, phase: .draining,
            message: phase == .completed ? "Finishing connection…" : "Cancelling… Waiting for pending network operations.",
            finishing: phase == .completed))
        onChange?()
        let drained = DispatchGroup()
        drained.enter(); worker.async { drained.leave() }
        if job.bluetoothID != nil {
            drained.enter()
            bluetooth.release { drained.leave() }
        }
        drained.notify(queue: .main) {
            guard self.attempt === job else { return }
            if let id = job.bluetoothID { self.releasedBluetooth = id }
            self.attempt = nil
            if phase == .completed {
                let count = photos.count
                self.session = Session(job: job, photoCount: count)
                if let id = job.bluetoothID, self.devices.revisions[id, default: 0] == job.bluetoothRevision {
                    let linked = job.initial.flatMap { self.preferences.revisions[$0.id, default: 0] == job.revisions[$0.id, default: 0] ? $0.id : nil }
                    self.devices.succeeded(id, network: linked, at: self.now())
                }
            }
            self.publish(ConnectionEvent(id: job.id, phase: phase, message: message,
                photos: photos, warning: warning))
            self.onChange?(); self.refreshCurrentNetwork()
        }
    }
}
