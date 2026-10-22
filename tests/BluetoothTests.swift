// All tests use injected radios. No CoreBluetooth manager or system pairing is created.
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

let wire = FakeBLETransport()
let prepared = try! runPreparation(wire).get()
check(prepared.identity.model == "RICOH GR IIIx" && prepared.credentials.ssid == "GR_TEST", "BLE identity and NUL-padded credentials decode")
let controlWrites = wire.writes.filter { $0.0 != RicohBLE.pairedDeviceName }
check(controlWrites.map(\.0) == [RicohBLE.power, RicohBLE.network] && controlWrites.allSatisfy { $0.1 == Data([1]) }, "Only documented conditional power/AP writes use one-byte ON")
check(wire.writes.first?.0 == RicohBLE.pairedDeviceName && wire.writes.first?.1 == Data("Fixture MacBook".utf8), "Computer Name is sent as UTF-8 paired-device name before camera activation")
check(wire.calls.firstIndex(of: "read:" + RicohBLE.mode)! < wire.calls.firstIndex(of: "write:" + RicohBLE.pairedDeviceName)!, "Protected identity and state checks precede paired-device naming")
check(wire.calls.firstIndex(of: "read:" + RicohBLE.model)! < wire.calls.firstIndex(of: "write:" + RicohBLE.power)!, "Supported identity precedes power writes")
let alreadyPrepared = FakeBLETransport()
alreadyPrepared.values[RicohBLE.power] = Data([1]); alreadyPrepared.values[RicohBLE.network] = Data([1])
_ = try! runPreparation(alreadyPrepared).get()
check(alreadyPrepared.writes.map(\.0) == [RicohBLE.pairedDeviceName], "Already-on/AP camera refreshes the Mac label without redundant radio writes")
let unicodeName = "Zoë’s MacBook Pro"
let unicodeNameTransport = FakeBLETransport()
_ = try! runPreparation(unicodeNameTransport, computerName: unicodeName).get()
check(unicodeNameTransport.writes.first?.1 == Data(unicodeName.utf8), "Unicode Computer Name is sent intact without an appended MAC address or terminator")
for missingName in [nil, "", " ", "Mac\0name"] as [String?] {
    let noName = FakeBLETransport()
    _ = try! runPreparation(noName, computerName: missingName).get()
    check(noName.writes.allSatisfy { $0.0 != RicohBLE.pairedDeviceName }, "Unavailable or invalid Computer Name does not write an invented label")
}
let unsupportedName = FakeBLETransport(); unsupportedName.nameWriteError = BluetoothFailure.unsupported
_ = try! runPreparation(unsupportedName).get()
check(unsupportedName.writes.contains { $0.0 == RicohBLE.network }, "Unsupported name characteristic does not block the Wi-Fi handoff")
let rejectedName = FakeBLETransport(); rejectedName.nameWriteError = BluetoothFailure.rejected
_ = try! runPreparation(rejectedName).get()
check(rejectedName.writes.filter { $0.0 == RicohBLE.pairedDeviceName }.count == 1, "Rejected name is best-effort without a retry loop")
let disconnectedName = FakeBLETransport(); disconnectedName.nameWriteError = BluetoothFailure.disconnected
check((try? runPreparation(disconnectedName).get()) == nil && disconnectedName.writes.allSatisfy { $0.0 == RicohBLE.pairedDeviceName }, "Lost BLE link during naming cannot advance to camera activation")
var currentComputerName = "Old Mac"
let renamedTransport = FakeBLETransport()
let renamedCamera = BluetoothCamera(transport: renamedTransport, computerName: { currentComputerName })
for name in ["Old Mac", "New Mac"] {
    currentComputerName = name
    var completedNaming = false
    renamedCamera.prepare(UUID(), identified: { _ in }, progress: { _ in }) { result in
        completedNaming = (try? result.get()) != nil
    }
    check(completedNaming, "Renamed Mac handoff succeeds")
    renamedCamera.release {}
}
check(renamedTransport.writes.filter { $0.0 == RicohBLE.pairedDeviceName }.map(\.1) == [Data("Old Mac".utf8), Data("New Mac".utf8)], "Reconnect obtains the latest Computer Name rather than caching it")
let rejected = FakeBLETransport(); rejected.rejectAP = true
check((try? runPreparation(rejected).get()) == nil && rejected.writes.filter { $0.0 == RicohBLE.network }.count == 1, "Application rejection never loops")
let unsupported = FakeBLETransport(); unsupported.values[RicohBLE.model] = Data("Other camera".utf8)
check((try? runPreparation(unsupported).get()) == nil && unsupported.writes.isEmpty, "Name candidates cannot authorize writes to unsupported models")
let unknownPower = FakeBLETransport(); unknownPower.values[RicohBLE.power] = Data([255])
check((try? runPreparation(unknownPower).get()) == nil && unknownPower.writes.isEmpty, "Unknown power cannot cause guessed writes")
let dropped = FakeBLETransport(); dropped.dropAP = true
check((try? runPreparation(dropped).get())?.apConfirmed == false, "AP-transition disconnect may return cached credentials requiring AP observation")
check((try? RicohBLE.text(Data([0xff]))) == nil, "Invalid UTF-8 rejected")
check((try? BluetoothWiFiCredentials(ssid: "camera", password: "short")) == nil, "Invalid WPA credential rejected")
check((try? BluetoothWiFiCredentials(ssid: "\0camera", password: "password")) == nil, "Embedded NUL SSID rejected")
check(try! RicohBLE.text(Data(" camera \0".utf8)) == " camera ", "Meaningful credential whitespace preserved")
let timeoutTransport = FakeBLETransport(); timeoutTransport.holdPower = true
let timeoutClock = TestClock()
let timeoutCamera = BluetoothCamera(transport: timeoutTransport, computerName: { "Fixture MacBook" }, later: timeoutClock.schedule)
var timeoutResults = 0
timeoutCamera.prepare(UUID(), identified: { _ in }, progress: { _ in }) { _ in timeoutResults += 1 }
timeoutClock.advance(165)
check(timeoutResults == 1, "BLE setup has a bounded completion")
timeoutCamera.release {}
timeoutTransport.heldPower?(.success(Data([1])))
check(timeoutResults == 1 && timeoutTransport.writes.isEmpty, "Late GATT response after retired preparation cannot write")
print("PASS: Bluetooth protocol, command order, conditional wake, credentials, rejection, AP drop and timeout isolation")

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
    var events: [[String: Any]] = []
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
        waitFor("Bluetooth coordinator terminal") { self.events.contains { terminalPhases.contains($0["phase"] as? String ?? "") } }
        check(events.last?["phase"] as? String == outcome, "Bluetooth connection outcome \(outcome)")
    }
}

let automatic = BluetoothRig()
automatic.start(); automatic.wait()
check(automatic.wifi.joinPasswords == ["ble-fixture-key"] && automatic.saved.reads.isEmpty && automatic.own.reads.isEmpty && automatic.own.writes.isEmpty, "BLE credentials bypass Keychain and remain ephemeral")
check(automatic.radio.releases == 1 && automatic.connection.isConnected && automatic.radio.connectedID == nil, "BLE release preserves verified Wi-Fi library")
check(automatic.devices.cameras.first?.connected != nil && automatic.devices.cameras.first?.networkID == cameraB.id, "Only verified handoff links camera and network")
check(automatic.events.description.contains("ble-fixture-key") == false && automatic.prefs.defaults.dictionary(forKey: "settings.v1")?.description.contains("ble-fixture-key") == false, "Events and preferences never expose BLE password")
automatic.connection.disconnectSession()
check(!automatic.connection.isConnected && automatic.wifi.joins.count == 1, "Disconnect clears session without network rollback")

let noPermission = BluetoothRig(); noPermission.auth.allowed = false
noPermission.start(); noPermission.wait("failed")
check(noPermission.radio.prepares == 0 && noPermission.wifi.joins.isEmpty, "Wi-Fi prerequisites checked before camera writes")

let retryKey = BluetoothRig(); retryKey.wifi.rejectedPasswords.insert("ble-fixture-key")
retryKey.start(); retryKey.wait("failed")
check(retryKey.radio.credentialReads == 1 && retryKey.wifi.joins.count == 2 && retryKey.saved.reads.isEmpty, "BLE credential refresh is bounded and cannot fall through to saved secrets")

let wrongCamera = BluetoothRig(); wrongCamera.camera.identityMatches = false
wrongCamera.start(); wrongCamera.wait("failed")
check(wrongCamera.prefs.networks.isEmpty && wrongCamera.devices.cameras.first?.connected == nil, "Wrong HTTP identity cannot publish history/library success")

let cancellation = BluetoothRig(); cancellation.radio.hold = true; cancellation.radio.holdRelease = true
cancellation.start()
waitFor("BLE preparation pending") { cancellation.radio.pending != nil }
cancellation.connection.cancelConnection()
check(cancellation.connection.isConnecting, "Cancellation retains admission while BLE disconnect drains")
cancellation.connection.connect(id: "too-soon", target: nil)
cancellation.radio.pending?(cancellation.radio.result)
check(cancellation.wifi.joins.isEmpty && cancellation.connection.isConnecting, "Late prepare cannot advance cancelled attempt")
cancellation.radio.releasePending?(); cancellation.wait("cancelled")
check(!cancellation.connection.isConnecting, "Drained cancellation unlocks connection admission")

let sleepy = BluetoothRig(); sleepy.radio.hold = true
sleepy.start(); waitFor("sleep setup pending") { sleepy.radio.pending != nil }
sleepy.connection.computerWillSleep(); sleepy.wait("cancelled")
sleepy.radio.pending?(sleepy.radio.result)
check(sleepy.wifi.joins.isEmpty, "Wake from computer sleep does not resume camera writes")

let history = BluetoothRig()
history.connection.selectTarget("bt:" + history.id.uuidString)
check(history.radio.prepares == 0 && history.wifi.joins.isEmpty, "Selection alone neither connects nor associates")
history.start(); history.wait()
let reloadedDevices = BluetoothDeviceStore(defaults: history.prefs.defaults)
check(reloadedDevices.preferred == history.id && reloadedDevices.cameras.count == 1, "Camera identity and explicit selection persist independently")
history.connection.forgetBluetooth(history.id.uuidString)
check(history.devices.cameras.count == 1, "Active session protects its remembered camera")
history.connection.disconnectSession()
history.connection.forget(cameraB.id)
waitFor("network unlink") { history.prefs.networks.isEmpty }
check(history.devices.cameras.first?.networkID == nil, "Forget network unlinks without forgetting its Bluetooth camera")
history.connection.forgetBluetooth(history.id.uuidString)
check(history.devices.cameras.isEmpty && history.own.removals == [cameraB.id], "Forget camera leaves independently owned network credentials alone")

let presence = BluetoothRig()
presence.connection.poll(discover: true); presence.connection.poll(discover: true)
check(presence.radio.discoveries == 1 && presence.radio.prepares == 0, "Throttled presence discovery never prepares camera")
presence.clock.advance(46)
let expired = presence.connection.bluetoothSettings()["bluetoothCameras"] as? [[String: Any]] ?? []
check(expired.isEmpty, "Expired unremembered availability is not displayed")
presence.radio.observations = [BluetoothObservation(id: presence.id, name: "GR_peer", seen: presence.clock.time, systemConnected: true)]
let systemState = presence.connection.bluetoothSettings()["bluetoothCameras"] as! [[String: Any]]
check(systemState.first?["status"] as? String == "Connected on Mac", "System BLE connection is distinct from app connection")
let inFlightJoin = BluetoothRig()
let joinGate = DispatchSemaphore(value: 0)
let joinStarted = ConnectionCancellation()
inFlightJoin.wifi.onJoin = { joinStarted.cancel(); _ = joinGate.wait(timeout: .now() + 10) }
inFlightJoin.start()
waitFor("blocking association entered") { joinStarted.isCancelled }
inFlightJoin.connection.cancelConnection()
check(inFlightJoin.connection.isConnecting, "Cancellation keeps a blocking CoreWLAN operation admitted until drain")
inFlightJoin.connection.connect(id: "overlap", target: nil)
joinGate.signal(); inFlightJoin.wait("cancelled")
check(inFlightJoin.camera.calls == 0 && inFlightJoin.prefs.networks.isEmpty && inFlightJoin.wifi.joined?.id == cameraB.id,
      "Late association is observed but cannot publish photos/history or start HTTP after cancel")
let queuedJoin = BluetoothRig()
let queueGate = DispatchSemaphore(value: 0)
let workerEntered = ConnectionCancellation()
queuedJoin.connection.worker.async { workerEntered.cancel(); _ = queueGate.wait(timeout: .now() + 10) }
waitFor("worker held before queued association") { workerEntered.isCancelled }
let queuedJob = CameraConnection.Attempt(id: "queued", target: cameraB.id, revisions: [:])
queuedJob.bluetoothID = queuedJoin.id
queuedJoin.connection.attempt = queuedJob
queuedJoin.connection.joinBluetooth(queuedJob, network: cameraB,
    credentials: try! BluetoothWiFiCredentials(ssid: cameraB.name, password: "fixture-key"))
queuedJoin.connection.cancelConnection(); queueGate.signal(); queuedJoin.wait("cancelled")
check(queuedJoin.wifi.joins.isEmpty, "Cancellation prevents an association queued but not started")
let adapterOff = BluetoothRig(); adapterOff.wifi.enabledValue = false
adapterOff.start(); adapterOff.wait("failed")
check(adapterOff.radio.prepares == 0, "Powered-off Mac Wi-Fi prevents BLE wake")

let fixtureVerifier = HTTPCameraVerification(base: fixtureURL)
let fixtureIdentity = BluetoothIdentity(id: UUID(), name: "Fixture", model: "RICOH GR IIIx", firmware: "1", serial: "fixture-serial")
var httpIdentity: Result<Void, Error>?
fixtureVerifier.identify(fixtureIdentity) { httpIdentity = $0 }
waitFor("HTTP props identity") { httpIdentity != nil }
check((try? httpIdentity!.get()) != nil, "Real HTTP verifier accepts expected model and comparable serial")
httpIdentity = nil
fixtureVerifier.identify(BluetoothIdentity(id: UUID(), name: "Fixture", model: "RICOH GR III", firmware: "1", serial: nil)) { httpIdentity = $0 }
waitFor("HTTP props mismatch") { httpIdentity != nil }
check((try? httpIdentity!.get()) == nil, "Real HTTP verifier rejects another camera model")
print("PASS: BLE/Wi-Fi handoff, credentials, identity, cancellation, sleep, presence, device history and independent Forget")

let bleUI = BluetoothRig()
let bleDownload = DownloadHandler(preferences: bleUI.prefs)
let bleController = AppController(preferences: bleUI.prefs, download: bleDownload, connection: bleUI.connection)
let bleConfig = WKWebViewConfiguration()
bleConfig.websiteDataStore = .nonPersistent()
bleConfig.userContentController.add(bleController, name: "app")
let bleWeb = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 360), configuration: bleConfig)
bleController.webView = bleWeb
let bluetoothWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
    styleMask: [.titled, .closable], backing: .buffered, defer: false)
bluetoothWindow.isReleasedWhenClosed = false
bluetoothWindow.contentView = bleWeb
bluetoothWindow.makeKeyAndOrderFront(nil)
bleWeb.loadHTMLString(APP_HTML, baseURL: nil)
waitFor("Bluetooth UI ready") { js("typeof doConnect", on: bleWeb) as? String == "function" }
bleController.pushSettings()
waitFor("Bluetooth option appears") { js("document.querySelectorAll('optgroup[label=\"Bluetooth cameras\"] option').length", on: bleWeb) as? Int == 1 }
_ = js("document.getElementById('networkSelect').value='bt:\(bleUI.id.uuidString)'; targetChanged();", on: bleWeb)
waitFor("native Bluetooth selection") { bleUI.connection.selectedBluetooth == bleUI.id }
check(bleUI.radio.prepares == 0, "WebKit target selection does not wake camera")
_ = js("doConnect();", on: bleWeb)
waitFor("real bridge Bluetooth completion") { js("connectedId !== null", on: bleWeb) as? Bool == true }
check(js("document.getElementById('connBtn').textContent", on: bleWeb) as? String == "DISCONNECT", "Primary action reflects verified session")
check(js("document.getElementById('networkSelect').selectedOptions[0].textContent", on: bleWeb) as? String == "GR_<test> · Released", "Selector safely displays the device name and truthful Bluetooth state")
check(js("document.getElementById('connectionPicker').dataset.mode === 'bluetooth' && getComputedStyle(document.querySelector('.bluetooth-icon')).display !== 'none' && getComputedStyle(document.querySelector('.wifi-icon')).display === 'none'", on: bleWeb) as? Bool == true, "Bluetooth target displays its mode icon")
check(js("document.querySelector('.transport-status') === null && document.getElementById('currentWiFi') === null", on: bleWeb) as? Bool == true, "Connection information has no duplicate Wi-Fi status row")
check(js("(() => { const p=document.getElementById('connectionPicker'), f=document.getElementById('findCameras'), c=document.getElementById('connBtn'), s=document.getElementById('settingsButton'), h=document.querySelector('header'); const boxes=[p,f,c,s].map(e=>e.getBoundingClientRect()); return p.nextElementSibling === f && boxes.every(b=>Math.abs(b.top+b.height/2-(boxes[0].top+boxes[0].height/2))<1 && b.right<=480) && h.getBoundingClientRect().height<60; })()", on: bleWeb) as? Bool == true, "Selector, Find cameras, connect and Settings stay on one line at minimum width")
check(js("document.getElementById('status').getAttribute('aria-live')", on: bleWeb) as? String == "polite", "Connection progress is accessible")
check(js("document.documentElement.scrollWidth <= 480", on: bleWeb) as? Bool == true, "Bluetooth controls fit minimum width")
_ = js("document.getElementById('dot').style.transition='none';", on: bleWeb)
let paintDeadline = Date().addingTimeInterval(0.4)
waitFor("connection indicator paint") { Date() >= paintDeadline }
let snapshotConfig = WKSnapshotConfiguration()
var snapshotDone = false
bleWeb.takeSnapshot(with: snapshotConfig) { picture, error in
    if let data = picture?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/bluetooth-ui.png"))
    }
    snapshotDone = true
}
waitFor("Bluetooth UI snapshot") { snapshotDone }
_ = js("doConnect();", on: bleWeb)
waitFor("UI disconnect") { !bleUI.connection.isConnected && js("connectedId === null", on: bleWeb) as? Bool == true }
bleUI.radio.hold = true; bleUI.radio.holdRelease = true
_ = js("doConnect();", on: bleWeb)
waitFor("UI pending BLE preparation") { bleUI.radio.pending != nil }
_ = js("doConnect();", on: bleWeb)
waitFor("UI cancellation drain") { js("document.getElementById('connBtn').textContent", on: bleWeb) as? String == "CANCELLING…" }
check(js("document.getElementById('connBtn').disabled && document.getElementById('networkSelect').disabled", on: bleWeb) as? Bool == true,
      "Cancellation button and target remain locked until native drain")
bleUI.radio.pending?(bleUI.radio.result)
bleUI.radio.releasePending?()
waitFor("UI cancellation finished") { js("connectionId === null", on: bleWeb) as? Bool == true }
bleUI.radio.hold = false; bleUI.radio.holdRelease = false; bleUI.radio.result = .failure(BluetoothFailure.rejected)
_ = js("doConnect();", on: bleWeb)
waitFor("UI manual recovery") { js("!document.getElementById('manualWiFi').hidden", on: bleWeb) as? Bool == true }
let previousPrepares = bleUI.radio.prepares
_ = js("useManualWiFi();", on: bleWeb)
waitFor("Manual route selected") { bleUI.connection.selectedBluetooth == nil }
check(bleUI.radio.prepares == previousPrepares && js("document.getElementById('networkSelect').value", on: bleWeb) as? String == "",
      "Manual recovery explicitly changes route without connecting or waking")
check(js("document.getElementById('connectionPicker').dataset.mode === 'wifi' && getComputedStyle(document.querySelector('.wifi-icon')).display !== 'none' && getComputedStyle(document.querySelector('.bluetooth-icon')).display === 'none'", on: bleWeb) as? Bool == true, "Explicit Wi-Fi route updates the mode icon")
bleUI.radio.observations.append(BluetoothObservation(id: UUID(), name: "GR_<test>", seen: bleUI.clock.time, systemConnected: false))
bleController.pushSettings()
waitFor("duplicate camera labels update") {
    js("(() => { const choices=Array.from(document.querySelectorAll('optgroup[label=\"Bluetooth cameras\"] option')); return choices.length===2 && new Set(choices.map(o=>o.textContent)).size===2; })()", on: bleWeb) as? Bool == true
}
bluetoothWindow.close()
print("PASS: real WebKit/native Bluetooth target, complete handoff, named state, disconnect, accessibility and minimum layout")
for domain in preferenceDomains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
