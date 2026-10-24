import Cocoa
import CoreWLAN
import CoreLocation
import Security
import Darwin

func runBluetoothProtocolTests() {
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
}

func runBluetoothTests() {
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
    let expired = presence.connection.settingsSnapshot().cameras
    check(expired.isEmpty, "Expired unremembered availability is not displayed")
    presence.radio.observations = [BluetoothObservation(id: presence.id, name: "GR_peer", seen: presence.clock.time, systemConnected: true)]
    let systemState = presence.connection.settingsSnapshot().cameras
    check(systemState.first?.status == "Connected on Mac", "System BLE connection is distinct from app connection")
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
}
