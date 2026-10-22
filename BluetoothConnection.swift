import Foundation

final class ConnectionCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

extension CameraConnection {
    func isLive(_ job: Attempt) -> Bool { attempt === job && job.terminal == nil }

    func pollBluetooth(discover: Bool) {
        guard discover, !isConnecting, canConnect(), !isConnected else { bluetooth.stopDiscovery(); return }
        let first = nextBluetoothDiscovery == .distantPast
        guard now() >= nextBluetoothDiscovery, first || !devices.cameras.isEmpty || selectedBluetooth != nil else { return }
        nextBluetoothDiscovery = now().addingTimeInterval(30)
        bluetooth.discover(explicit: false)
        onChange?()
    }
    func findBluetooth() {
        guard !isConnecting, !isConnected, canConnect() else { return }
        nextBluetoothDiscovery = now().addingTimeInterval(30)
        bluetooth.discover(explicit: true); onChange?()
    }
    func selectTarget(_ target: String) {
        guard !isConnecting, !isConnected, canConnect() else { return }
        if target.hasPrefix("bt:"), let id = UUID(uuidString: String(target.dropFirst(3))) {
            guard devices.cameras.contains(where: { $0.identity.id == id }) || bluetooth.observations.contains(where: { $0.id == id }) else { return }
            selectedBluetooth = id; devices.select(id)
        } else {
            guard target.isEmpty || preferences.networks.contains(where: { $0.network.id == target }) else { return }
            selectedBluetooth = nil; devices.select(nil)
        }
        selectionRevision += 1; manualRecovery = false; onChange?()
    }
    func forgetBluetooth(_ raw: String) {
        guard let id = UUID(uuidString: raw), !isConnecting, canConnect(), session?.bluetoothID != id else { return }
        devices.forget(id)
        if selectedBluetooth == id { selectedBluetooth = nil; selectionRevision += 1 }
        if releasedBluetooth == id { releasedBluetooth = nil }
        onChange?()
    }
    func cancelConnection() {
        guard let job = attempt, isLive(job) else { return }
        finish(job, phase: "cancelled", message: "Connection cancelled. Camera power or Wi-Fi may already have changed.")
    }
    func disconnectSession() {
        guard !isConnecting, canConnect(), let connected = session else { return }
        session = nil; healthCheck = nil; health.cancel(); scanGeneration += 1
        onEvent?(["id": connected.id, "phase": "disconnected", "message": "Disconnected from camera. Wi-Fi association unchanged."])
        onChange?()
    }
    func computerWillSleep() {
        bluetooth.stopDiscovery()
        if let job = attempt, isLive(job) {
            finish(job, phase: "cancelled", message: "Connection interrupted by sleep. Press CONNECT to try again.")
        }
    }

    func beginBluetooth(_ job: Attempt, id: UUID) {
        guard devices.cameras.contains(where: { $0.identity.id == id }) || bluetooth.observations.contains(where: { $0.id == id }) else {
            finish(job, error: appError("That Bluetooth camera is no longer known. Use Find cameras.")); return
        }
        selectedBluetooth = id; devices.select(id); releasedBluetooth = nil
        event(job, phase: "preparing", message: "Checking Wi-Fi access before Bluetooth setup…")
        authorization.request { allowed in
            guard self.isLive(job) else { return }
            guard allowed else {
                self.finish(job, error: appError("Allow Location Services for automatic camera Wi-Fi joining, or use Current Wi-Fi.")); return
            }
            self.worker.async {
                let enabled = self.wifi.enabled()
                DispatchQueue.main.async {
                    guard self.isLive(job) else { return }
                    guard enabled else { self.finish(job, error: appError("Turn on Mac Wi-Fi before connecting the Bluetooth camera.")); return }
                    self.bluetooth.prepare(id, identified: { identity in
                        guard self.isLive(job), self.devices.revisions[id, default: 0] == job.bluetoothRevision else { return }
                        job.bluetoothIdentity = identity
                        self.devices.remember(identity, at: self.now()); self.onChange?()
                    }, progress: { message in
                        guard self.isLive(job) else { return }
                        self.bluetoothLabel = message
                        self.event(job, phase: "bluetooth", message: message); self.onChange?()
                    }, completion: { result in
                        guard self.isLive(job) else { return }
                        switch result {
                        case .failure(let error): self.finish(job, error: error)
                        case .success(let handoff):
                            job.bluetoothIdentity = handoff.identity; job.bluetoothCredentials = handoff.credentials
                            job.target = CameraNetwork(name: handoff.credentials.ssid).id
                            job.deadline = self.now().addingTimeInterval(45)
                            self.later(45) {
                                if self.isLive(job), !job.verified {
                                    self.finish(job, error: appError("Camera Wi-Fi setup timed out. Use camera Wi-Fi or retry."))
                                }
                            }
                            self.seekBluetoothNetwork(job)
                        }
                    })
                }
            }
        }
    }

    func seekBluetoothNetwork(_ job: Attempt) {
        guard isLive(job), let target = job.target, let deadline = job.deadline else { return }
        event(job, phase: "waiting", message: "Waiting for camera Wi-Fi…")
        worker.async {
            let result = Result { try self.wifi.scan().first { $0.id == target } }
            let current = self.wifi.current()
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                if let network = try? result.get(), let credentials = job.bluetoothCredentials {
                    if current?.id == target {
                        job.initial = network
                        self.startVerification(job, network: network, waitForNetwork: true)
                    } else { self.joinBluetooth(job, network: network, credentials: credentials) }
                } else if self.now() < deadline {
                    self.later(0.75) { self.seekBluetoothNetwork(job) }
                } else { self.finish(job, error: appError("Camera Wi-Fi did not appear. Turn it on at the camera and use the Wi-Fi route.")) }
            }
        }
    }

    func joinBluetooth(_ job: Attempt, network: CameraNetwork, credentials: BluetoothWiFiCredentials) {
        guard isLive(job), job.target == network.id else { return }
        event(job, phase: "joining", message: "Joining \(network.name)…")
        worker.async {
            guard !job.cancellation.isCancelled else { return }
            let result = Result { try self.wifi.join(network, password: credentials.password) }
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                switch result {
                case .success:
                    job.initial = network
                    self.startVerification(job, network: network, waitForNetwork: true)
                case .failure:
                    guard !job.credentialRefreshed, self.bluetooth.connectedID == job.bluetoothID else {
                        self.finish(job, error: appError("Could not join camera Wi-Fi using Bluetooth credentials. Use camera Wi-Fi or retry.")); return
                    }
                    job.credentialRefreshed = true
                    self.bluetooth.refreshCredentials { result in
                        guard self.isLive(job) else { return }
                        switch result {
                        case .failure(let error): self.finish(job, error: error)
                        case .success(let credentials):
                            job.bluetoothCredentials = credentials; job.target = CameraNetwork(name: credentials.ssid).id
                            self.seekBluetoothNetwork(job)
                        }
                    }
                }
            }
        }
    }

    func bluetoothSettings() -> [String: Any] {
        let observed = bluetooth.observations.filter { now().timeIntervalSince($0.seen) <= 45 }
        let active = attempt?.bluetoothID ?? session?.bluetoothID
        let display = active ?? selectedBluetooth ?? bluetooth.connectedID ?? observed.first(where: \.systemConnected)?.id
        let ids = Set(devices.cameras.map { $0.identity.id } + observed.map(\.id) + (display.map { [$0] } ?? []))
        let rows = ids.map { id -> [String: Any] in
            let known = devices.cameras.first { $0.identity.id == id }
            let nearby = observed.first { $0.id == id }
            let status: String
            if bluetooth.connectedID == id { status = "Connected" }
            else if attempt?.bluetoothID == id, attempt?.terminal == nil { status = "Connecting" }
            else if releasedBluetooth == id { status = "Released" }
            else if nearby?.systemConnected == true { status = "Connected on Mac" }
            else if nearby != nil { status = "Available" }
            else { status = "Remembered · Not seen" }
            return ["id": "bt:" + id.uuidString, "deviceID": id.uuidString,
                "name": known?.identity.model ?? nearby?.name ?? "Ricoh camera",
                "deviceName": known?.identity.name ?? nearby?.name ?? "Ricoh camera", "status": status,
                "remembered": known != nil, "active": active == id || isConnecting || !canConnect(),
                "firmware": known?.identity.firmware ?? ""]
        }.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        let shown = rows.first { $0["deviceID"] as? String == display?.uuidString }
        return ["bluetoothCameras": rows, "bluetoothState": bluetooth.state,
            "bluetoothName": shown?["deviceName"] as? String ?? "", "bluetoothStatus": shown?["status"] as? String ?? "",
            "preferredTarget": selectedBluetooth.map { "bt:" + $0.uuidString } ?? "",
            "selectionRevision": selectionRevision, "connectionBusy": isConnecting, "cameraConnected": isConnected,
            "connectionDraining": attempt?.terminal != nil, "connectionFinishing": attempt?.terminal == "completed", "manualRecovery": manualRecovery,
            "bluetoothControlsDisabled": isConnecting || isConnected || !canConnect()]
    }
}
