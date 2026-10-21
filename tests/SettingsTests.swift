// Native preferences and publishing checks use isolated domains and temporary folders.
let prefsDomain = "GRBrowser.preference-tests.\(UUID().uuidString)"
let isolatedDefaults = UserDefaults(suiteName: prefsDomain)!
let preferences = AppPreferences(defaults: isolatedDefaults)
check(preferences.format == .zip && preferences.folder() == nil && preferences.networks.isEmpty, "Preference defaults")
let folder = testRoot.appendingPathComponent("chosen-folder")
try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
try! preferences.setFolder(folder)
preferences.setFormat(.separate)
let cameraA = CameraNetwork(name: "GR_A")
let cameraB = CameraNetwork(name: "GR_B")
preferences.remember(cameraA, at: Date(timeIntervalSince1970: 5))
preferences.remember(cameraA, at: Date(timeIntervalSince1970: 10))
let reopened = AppPreferences(defaults: isolatedDefaults)
check(reopened.format == .separate && reopened.folder()?.path == folder.path && reopened.networks.count == 1,
      "Preferences and deduplicated history survive reload")
let moved = testRoot.appendingPathComponent("moved-folder")
try! fm.moveItem(at: folder, to: moved)
check(preferences.folder()?.path == moved.path, "Folder bookmark follows a move")
try! fm.removeItem(at: moved)
check(preferences.folder().map(AppPreferences.usableFolder) != true, "Missing destination is unusable")
preferences.forget(cameraA.id)
check(AppPreferences(defaults: isolatedDefaults).networks.isEmpty, "Forgotten history stays removed after reload")
isolatedDefaults.set(["version": 1, "format": "broken", "folder": "wrong", "networks": [["id": "invalid"]]], forKey: "settings.v1")
let invalid = AppPreferences(defaults: isolatedDefaults)
check(invalid.format == .zip && invalid.folder() == nil && invalid.networks.isEmpty, "Invalid preference fields fall back safely")
isolatedDefaults.removePersistentDomain(forName: prefsDomain)
print("PASS: preference defaults, persistence, corruption, bookmarks, and history")

let separate = runDownload("separate", files: ["DCIM/same.JPG", "OTHER/same.JPG"], setup: { handler, _ in
    handler.preferences.setFormat(.separate)
    try! Data("existing".utf8).write(to: handler.destination!.appendingPathComponent("same.JPG"))
})
check(separate.saved.map(\.lastPathComponent) == ["same (1).JPG", "same (2).JPG"], "Duplicate basenames receive suffixes")
check(try! String(contentsOf: separate.destination!.appendingPathComponent("same.JPG"), encoding: .utf8) == "existing", "Existing file preserved")
check(!separate.events.contains { $0["phase"] as? String == "archiving" }, "Separate exports skip ZIP creation")

let partial = runDownload("partial-save", files: ["DCIM/one.JPG", "DCIM/two.JPG"], expected: "failed", setup: { handler, _ in
    handler.preferences.setFormat(.separate); handler.failAfter = 1
})
check(partial.saved.count == 1 && (partial.terminal?["message"] as? String)?.contains("1/2 saved") == true,
      "Partial save retains completed files and reports accurate failure count")

let snapshot = runDownload("snapshot", files: ["DCIM/one.JPG", "DCIM/two.JPG"], setup: { handler, _ in
    var changed = false
    handler.onEvent = { event in
        if !changed && event["phase"] as? String == "downloading" {
            changed = true
            let replacement = testRoot.appendingPathComponent("replacement-folder")
            try! fm.createDirectory(at: replacement, withIntermediateDirectories: true)
            try! handler.preferences.setFolder(replacement)
            handler.preferences.setFormat(.separate)
        }
    }
})
check(snapshot.saved.count == 1 && snapshot.saved[0].pathExtension == "zip"
      && snapshot.saved[0].deletingLastPathComponent().path == snapshot.destination!.path, "Active operation freezes folder and format")
snapshot.saved = []
snapshot.startDownload(id: "snapshot-next", files: ["DCIM/one.JPG", "DCIM/two.JPG"])
waitFor("updated preferences next download") { snapshot.saved.count == 2 && snapshot.terminal?["id"] as? String == "snapshot-next" }
check(snapshot.saved.allSatisfy { $0.pathExtension == "JPG" && $0.deletingLastPathComponent().path == snapshot.preferences.folder()?.path },
      "Next download uses updated folder and format")

let picker = runDownload("choose-before-transfer", expected: "cancelled", cancel: true, setup: { handler, _ in
    handler.onChoose = {
        check(!handler.events.contains { $0["phase"] as? String == "downloading" }, "No transfer before destination selection")
        handler.startDownload(id: "duplicate-picker", files: ["DCIM/slow.JPG"])
    }
})
check(picker.chooseCount == 1 && picker.preferences.folder() == nil && picker.saved.isEmpty, "Picker cancellation and admission guard")
let firstFolder = runDownload("first-folder", cancel: true, setup: { handler, _ in
    handler.destination = testRoot.appendingPathComponent("first-folder/output")
})
check(firstFolder.chooseCount == 1 && firstFolder.preferences.folder()?.path == firstFolder.destination?.path,
      "First chosen directory is persisted before transferring")
let oldZip = batch.saved[0]
let oldZipBytes = try! Data(contentsOf: oldZip)
batch.saved = []
batch.startDownload(id: "zip-collision", files: ["DCIM/slow.JPG", "OTHER/second.JPG"])
waitFor("ZIP collision") { batch.saved.count == 1 && batch.terminal?["id"] as? String == "zip-collision" }
check(batch.saved[0] != oldZip && batch.saved[0].lastPathComponent.contains("(1)")
      && (try! Data(contentsOf: oldZip)) == oldZipBytes, "Existing ZIP remains unchanged")
// Test concurrent publishers independently of camera transfer timing.
let collisionSource = testRoot.appendingPathComponent("collision.JPG")
try! Data("photo".utf8).write(to: collisionSource)
let collisions = testRoot.appendingPathComponent("collisions")
try! fm.createDirectory(at: collisions, withIntermediateDirectories: true)
let publisher = DownloadHandler(preferences: testPreferences())
let publishLock = NSLock()
var publications: [URL] = []
DispatchQueue.concurrentPerform(iterations: 8) { _ in
    let output = try! publisher.publishFile(collisionSource, in: collisions)
    publishLock.lock(); publications.append(output); publishLock.unlock()
}
check(Set(publications).count == 8 && publications.allSatisfy { (try? Data(contentsOf: $0)) == Data("photo".utf8) },
      "Concurrent exclusive publishing preserves every output")
check(try! fm.contentsOfDirectory(atPath: collisions.path).count == 8, "No partial publishing artifacts remain")
print("PASS: separate exports, collision races, snapshot isolation, cancellation, and partial saves")

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
    lazy var connection = CameraConnection(preferences: prefs, wifi: wifi, authorization: auth, credentials: credentials,
                                           savedCredentials: savedCredentials, camera: camera, health: health,
                                           now: { self.clock.time }, later: clock.schedule)
    var events: [[String: Any]] = []
    init() {
        prefs.remember(cameraA, at: Date(timeIntervalSince1970: 1))
        prefs.remember(cameraB, at: Date(timeIntervalSince1970: 2))
        connection.onEvent = { self.events.append($0) }
        connection.passwordPrompt = { _, done in done(("fixture-secret", true)) }
    }
    func start(_ id: String = "attempt", target: String? = cameraB.id) { connection.connect(id: id, target: target) }
    func wait(_ phase: String = "completed") {
        waitFor("connection outcome") { self.events.contains { terminalPhases.contains($0["phase"] as? String ?? "") } }
        check(events.last?["phase"] as? String == phase, "Expected connection \(phase), got \(events.last ?? [:])")
    }
}

let reconnect = ConnectionRig()
reconnect.camera.onVerify = { check(reconnect.wifi.joins == [cameraB.id], "Join precedes camera verification") }
reconnect.start(); reconnect.start("duplicate"); reconnect.wait()
check(reconnect.wifi.joins.count == 1 && reconnect.credentials.values[cameraB.id] == "fixture-secret", "Reconnect uses one attempt and remembers opted-in verified password")
check(reconnect.prefs.networks.count == 2 && reconnect.prefs.networks.first?.network.id == cameraB.id, "Valid empty camera list updates history without duplication")
check(!String(describing: reconnect.connection.settingsValue()).contains("fixture-secret") && !String(describing: reconnect.events).contains("fixture-secret"), "Credentials never enter settings or UI events")

// The native saved-Wi-Fi adapter is tested through its API boundary; never read real Wi-Fi secrets.
var keychainDomains: [CWKeychainDomain] = []
let systemPassword = MacWiFiCredentials { domain, ssid in
    keychainDomains.append(domain)
    check(ssid == Data(base64Encoded: cameraB.id), "Saved Wi-Fi lookup uses only the selected exact SSID bytes")
    return domain == .user ? (errSecItemNotFound, nil) : (errSecSuccess, "macos-fixture-secret")
}
check(try! systemPassword.password(for: cameraB.id) == "macos-fixture-secret"
      && keychainDomains == [.user, .system], "Saved Wi-Fi lookup searches user then system Keychain")
keychainDomains = []
let userPassword = MacWiFiCredentials { domain, _ in
    keychainDomains.append(domain); return (errSecSuccess, "user-fixture-secret")
}
check(try! userPassword.password(for: cameraB.id) == "user-fixture-secret" && keychainDomains == [.user],
      "User Keychain match avoids another authorization request")
for status in [errSecItemNotFound, errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable] {
    var calls = 0
    let unavailable = MacWiFiCredentials { _, _ in calls += 1; return (status, nil) }
    check(try! unavailable.password(for: cameraB.id) == nil && calls == (status == errSecItemNotFound ? 2 : 1),
          "Missing or inaccessible macOS credentials allow fallback without repeated access requests")
}
var cancelledLookup = false
do { _ = try MacWiFiCredentials { _, _ in (errSecUserCanceled, nil) }.password(for: cameraB.id) }
catch SavedWiFiCredentialError.cancelled { cancelledLookup = true }
catch { check(false, "Unexpected saved Keychain cancellation result") }
check(cancelledLookup, "Explicit macOS Keychain cancellation remains distinct from a missing password")
var invalidLookupCalled = false
do {
    _ = try MacWiFiCredentials { _, _ in invalidLookupCalled = true; return (errSecSuccess, "unused") }.password(for: "invalid")
    check(false, "Invalid SSID identity must fail")
} catch { check(!invalidLookupCalled, "Invalid SSIDs do not query Keychain") }

let macPreferred = ConnectionRig()
macPreferred.savedCredentials.values[cameraB.id] = "macos-fixture-secret"
macPreferred.credentials.values[cameraB.id] = "app-fixture-secret"
var preferredPrompts = 0
macPreferred.connection.passwordPrompt = { _, _ in preferredPrompts += 1 }
macPreferred.start(); macPreferred.wait()
check(macPreferred.wifi.joinPasswords == ["macos-fixture-secret"] && macPreferred.credentials.reads.isEmpty
      && preferredPrompts == 0 && macPreferred.credentials.writes.isEmpty,
      "macOS saved password takes priority without manual entry or copying into the app Keychain")
check(!String(describing: macPreferred.connection.settingsValue()).contains("macos-fixture-secret")
      && !String(describing: macPreferred.events).contains("macos-fixture-secret"), "macOS passwords never enter UI events or preferences")
macPreferred.connection.forget(cameraB.id)
waitFor("forget after macOS credential reuse") { !macPreferred.prefs.networks.contains { $0.network.id == cameraB.id } }
check(macPreferred.savedCredentials.values[cameraB.id] == "macos-fixture-secret"
      && macPreferred.savedCredentials.removals.isEmpty && macPreferred.savedCredentials.writes.isEmpty,
      "Forget cannot remove or modify macOS-owned passwords")
check(macPreferred.connection.settingsValue()["currentName"] as? String == cameraB.name,
      "Forgetting the currently joined network preserves its current Wi-Fi name")
let appFallback = ConnectionRig()
appFallback.credentials.values[cameraB.id] = "app-fixture-secret"
appFallback.connection.passwordPrompt = { _, _ in check(false, "Existing app password should skip manual entry") }
appFallback.start(); appFallback.wait()
check(appFallback.savedCredentials.reads == [cameraB.id] && appFallback.credentials.reads == [cameraB.id]
      && appFallback.wifi.joinPasswords == ["app-fixture-secret"], "Missing macOS password falls back to the app Keychain")
let oldMacPassword = ConnectionRig()
oldMacPassword.savedCredentials.values[cameraB.id] = "old-fixture-secret"
oldMacPassword.credentials.values[cameraB.id] = "app-fixture-secret"
oldMacPassword.wifi.rejectedPasswords = ["old-fixture-secret"]
oldMacPassword.start(); oldMacPassword.wait()
check(oldMacPassword.wifi.joinPasswords == ["old-fixture-secret", "app-fixture-secret"]
      && oldMacPassword.savedCredentials.writes.isEmpty, "Rejected macOS password falls back without changing the system credential")
let repeatedPassword = ConnectionRig()
repeatedPassword.savedCredentials.values[cameraB.id] = "old-fixture-secret"
repeatedPassword.credentials.values[cameraB.id] = "old-fixture-secret"
repeatedPassword.wifi.rejectedPasswords = ["old-fixture-secret"]
repeatedPassword.connection.passwordPrompt = { _, done in done(("new-fixture-secret", false)) }
repeatedPassword.start(); repeatedPassword.wait()
check(repeatedPassword.wifi.joinPasswords == ["old-fixture-secret", "new-fixture-secret"],
      "The same rejected saved password is not retried from another Keychain source")
let keychainCancelled = ConnectionRig()
keychainCancelled.savedCredentials.cancelRead = true
keychainCancelled.connection.passwordPrompt = { _, _ in check(false, "Cancelled Keychain access must not open another password prompt") }
keychainCancelled.start(); keychainCancelled.wait("cancelled")
check(keychainCancelled.wifi.joins.isEmpty && keychainCancelled.credentials.reads.isEmpty,
      "Keychain cancellation stops the attempt before fallback or association")
let openNetwork = ConnectionRig()
openNetwork.wifi.networks = [CameraNetwork(name: cameraB.name, secured: false)]
openNetwork.start(); openNetwork.wait()
check(openNetwork.savedCredentials.reads.isEmpty && openNetwork.credentials.reads.isEmpty && openNetwork.wifi.joinPasswords == [nil],
      "Open Wi-Fi association never queries either Keychain")
print("PASS: macOS Keychain priority, exact SSIDs, app/manual fallback, rejected passwords, cancellation, and read-only Forget")

let already = ConnectionRig(); already.start(target: cameraA.id); already.wait()
check(already.wifi.joins.isEmpty && already.savedCredentials.reads.isEmpty && already.credentials.reads.isEmpty,
      "Already joined skips association and all credential access")
let manual = ConnectionRig(); manual.auth.allowed = false; manual.start(target: nil); manual.wait()
check(manual.wifi.joins.isEmpty && manual.prefs.networks.allSatisfy { $0.lastConnected.timeIntervalSince1970 < 100 }, "Denied authorization preserves manual connection without inventing history")
manual.connection.refresh()
check(manual.connection.nearby.isEmpty && !manual.connection.notice.isEmpty, "Denied discovery has actionable fallback")
check((manual.events.last?["warning"] as? String)?.contains("Location Services") == true,
      "Successful manual connection explains why the network was not remembered")
let discovered = ConnectionRig(); discovered.connection.refresh()
waitFor("discovery") { discovered.connection.nearby.count == 2 }
check(discovered.wifi.joins.isEmpty && discovered.camera.calls == 0 && discovered.savedCredentials.reads.isEmpty,
      "Discovery does not join, access passwords, or contact camera")

let laterNetwork = ConnectionRig()
var discoveryUpdates = 0
laterNetwork.connection.onChange = { discoveryUpdates += 1 }
laterNetwork.wifi.networks = []; laterNetwork.wifi.joined = nil
laterNetwork.connection.refresh()
waitFor("initial empty scan") { discoveryUpdates == 1 }
laterNetwork.wifi.networks = [cameraB]
laterNetwork.clock.advance(9); laterNetwork.connection.poll()
check(laterNetwork.wifi.scans == 1, "Discovery is throttled between scans")
laterNetwork.clock.advance(1); laterNetwork.connection.poll()
waitFor("camera appears after launch") { laterNetwork.connection.nearby.map(\.id) == [cameraB.id] }
check(laterNetwork.wifi.scans == 2 && laterNetwork.auth.requests == 0 && laterNetwork.wifi.joins.isEmpty
      && laterNetwork.camera.calls == 0, "Periodic discovery detects a late camera without prompting, joining, or verifying it")
laterNetwork.wifi.networks = []
laterNetwork.clock.advance(10); laterNetwork.connection.poll()
waitFor("camera disappears from discovery") { laterNetwork.connection.nearby.isEmpty }
laterNetwork.wifi.networks = [cameraB]
laterNetwork.clock.advance(10); laterNetwork.connection.poll(discover: false)
check(laterNetwork.wifi.scans == 3, "Inactive app polling skips discovery")
laterNetwork.connection.canConnect = { false }; laterNetwork.connection.poll()
check(laterNetwork.wifi.scans == 3, "Automatic scans do not overlap a download")
laterNetwork.connection.canConnect = { true }; laterNetwork.connection.poll()
waitFor("discovery resumes after download") { laterNetwork.connection.nearby.count == 1 }
laterNetwork.auth.allowed = false; laterNetwork.clock.advance(10); laterNetwork.connection.poll()
check(laterNetwork.wifi.scans == 4 && laterNetwork.auth.requests == 0, "Polling never prompts or scans without permission")
laterNetwork.auth.allowed = true; laterNetwork.connection.poll()
waitFor("discovery resumes after authorization") { discoveryUpdates == 5 }
laterNetwork.prefs.forget(cameraA.id); laterNetwork.prefs.forget(cameraB.id)
laterNetwork.clock.advance(10); laterNetwork.connection.poll()
check(laterNetwork.wifi.scans == 5, "No periodic scans when there are no remembered targets")
let scanningAttempt = ConnectionRig(); scanningAttempt.camera.hold = true; scanningAttempt.start()
waitFor("connecting before discovery tick") { scanningAttempt.camera.pending.count == 1 }
let attemptScans = scanningAttempt.wifi.scans
scanningAttempt.connection.poll()
check(scanningAttempt.wifi.scans == attemptScans, "Automatic scans do not overlap connection setup")
scanningAttempt.camera.pending.removeFirst()(.success([])); scanningAttempt.wait()
print("PASS: late camera discovery, scan throttling, permission recovery, and download/connection guards")

let currentOnly = ConnectionRig()
currentOnly.prefs.forget(cameraA.id); currentOnly.prefs.forget(cameraB.id)
let homeNetwork = CameraNetwork(name: "Home <& Wi-Fi>")
currentOnly.wifi.joined = homeNetwork; currentOnly.connection.poll()
waitFor("current Wi-Fi without history") { currentOnly.connection.settingsValue()["currentName"] as? String == homeNetwork.name }
check(currentOnly.wifi.scans == 0 && currentOnly.wifi.joins.isEmpty, "Current Wi-Fi display does not require scanning or remembered networks")
currentOnly.connection.canConnect = { false }
currentOnly.wifi.joined = cameraA; currentOnly.connection.poll()
waitFor("current Wi-Fi while downloading") { currentOnly.connection.settingsValue()["currentName"] as? String == cameraA.name }
check(currentOnly.wifi.scans == 0, "Current interface updates while downloads prohibit scanning")
currentOnly.wifi.joined = nil; currentOnly.wifi.readyValue = false; currentOnly.connection.poll()
waitFor("Wi-Fi disconnected without history") { currentOnly.connection.settingsValue()["wifiConnected"] as? Bool == false }
check(currentOnly.connection.currentID == nil && currentOnly.connection.settingsValue()["currentName"] as? String == "",
      "Lost Wi-Fi clears its current name without inventing another network")
currentOnly.auth.allowed = false; currentOnly.wifi.joined = homeNetwork; currentOnly.wifi.readyValue = true
currentOnly.connection.poll()
waitFor("SSID hidden by authorization") { currentOnly.connection.settingsValue()["wifiConnected"] as? Bool == true }
check(currentOnly.connection.settingsValue()["currentName"] as? String == "", "Unavailable names remain explicit while connection readiness is still visible")

let disappeared = ConnectionRig(); disappeared.wifi.networks = [cameraA]; disappeared.start(); disappeared.wait("failed")
check(disappeared.camera.calls == 0 && disappeared.wifi.joins.isEmpty, "Disappeared target stops before camera requests")
let joinFailed = ConnectionRig(); joinFailed.wifi.joinError = true; joinFailed.start(); joinFailed.wait("failed")
check(joinFailed.camera.calls == 0 && joinFailed.prefs.networks.first?.lastConnected.timeIntervalSince1970 == 2, "Join failure does not verify or update history")
let notReady = ConnectionRig(); notReady.wifi.readyValue = false; notReady.start()
waitFor("readiness polling") { notReady.wifi.readinessChecks > 0 }
notReady.clock.advance(16); notReady.wait("failed")
check(notReady.camera.calls == 0, "Readiness timeout is bounded")
let stale = ConnectionRig(); stale.camera.hold = true; stale.start()
waitFor("held camera response") { stale.camera.pending.count == 1 }
let obsolete = stale.camera.pending.removeFirst()
stale.clock.advance(16); stale.wait("failed")
stale.events = []; stale.camera.hold = false; stale.start("new", target: cameraB.id); stale.wait()
let count = stale.events.count
obsolete(.success([CameraPhoto(dir: "bad", file: "stale.JPG")]))
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(stale.events.count == count && stale.events.last?["id"] as? String == "new", "Late responses cannot replace the next attempt")

let badCamera = ConnectionRig()
badCamera.camera.result = .failure(appError("Could not load camera photos."))
badCamera.start()
waitFor("failed camera response") { badCamera.camera.calls > 0 }
badCamera.clock.advance(16); badCamera.wait("failed")
check(badCamera.events.last?["message"] as? String == "Could not load camera photos."
      && badCamera.prefs.networks.first?.lastConnected.timeIntervalSince1970 == 2,
      "Photo-list error remains distinct and cannot update network history")
let cancelled = ConnectionRig(); cancelled.connection.passwordPrompt = { _, done in done(nil) }; cancelled.start(); cancelled.wait("cancelled")
check(cancelled.wifi.joins.isEmpty && cancelled.camera.calls == 0, "Password cancellation has no network side effects")
let noRemember = ConnectionRig(); noRemember.connection.passwordPrompt = { _, done in done(("temporary-secret", false)) }; noRemember.start(); noRemember.wait()
check(noRemember.credentials.values.isEmpty, "Unremembered password stays out of Keychain")
let readFailed = ConnectionRig(); readFailed.credentials.failRead = true; readFailed.start(); readFailed.wait("failed")
check(readFailed.wifi.joins.isEmpty, "Keychain read failure does not associate")
let writeFailed = ConnectionRig(); writeFailed.credentials.failWrite = true; writeFailed.start(); writeFailed.wait()
check(writeFailed.events.last?["warning"] as? String == "Keychain write failed" && writeFailed.credentials.values.isEmpty, "Credential write error is surfaced without claiming storage")

let forgotten = ConnectionRig(); forgotten.camera.hold = true; forgotten.start()
waitFor("forget during verification") { forgotten.camera.pending.count == 1 }
forgotten.connection.forget(cameraB.id)
waitFor("history removed") { !forgotten.prefs.networks.contains { $0.network.id == cameraB.id } }
forgotten.camera.pending.removeFirst()(.success([])); forgotten.wait()
check(!forgotten.prefs.networks.contains { $0.network.id == cameraB.id } && forgotten.credentials.values[cameraB.id] == nil, "Forget survives late success and does not re-create a password")
forgotten.events = []; forgotten.camera.hold = false; forgotten.start("learn-again", target: nil); forgotten.wait()
check(forgotten.prefs.networks.contains { $0.network.id == cameraB.id }, "New manual success relearns a forgotten network")
let deleteFailed = ConnectionRig(); deleteFailed.credentials.failDelete = true; deleteFailed.connection.forget(cameraA.id)
waitFor("credential deletion error") { deleteFailed.connection.notice == "Keychain delete failed" }
check(deleteFailed.prefs.networks.contains { $0.network.id == cameraA.id }, "Deletion error leaves row for retry")
let blocked = ConnectionRig(); blocked.connection.canConnect = { false }; blocked.start()
check(blocked.events.isEmpty && blocked.wifi.joins.isEmpty, "Native connection guard rejects downloads overlap")
let blockedDownload = DownloadHandler(preferences: testPreferences()); blockedDownload.canStart = { false }
blockedDownload.startDownload(id: "blocked", files: ["DCIM/one.JPG"])
check(!blockedDownload.isDownloading, "Native download guard rejects connection overlap")
print("PASS: discovery, reconnect sequencing, permissions, readiness, credentials, Forget races, and stale attempts")

check(MacWiFi.network(name: cameraA.name, data: nil, secured: true)?.id == cameraA.id,
      "A readable SSID string is enough to identify the network")
check(MacWiFi.network(name: nil, data: Data(cameraA.name.utf8), secured: true)?.name == cameraA.name,
      "A readable raw SSID is enough to display and identify the network")
check(MacWiFi.network(name: nil, data: nil, secured: true) == nil,
      "Unavailable Wi-Fi identity is not fabricated")
let firstManual = ConnectionRig()
firstManual.prefs.forget(cameraA.id); firstManual.prefs.forget(cameraB.id)
firstManual.start(target: nil); firstManual.wait()
check(firstManual.connection.isConnected && firstManual.prefs.networks.map(\.network.id) == [cameraA.id],
      "First successful Current Wi-Fi connection adds a network to an empty list")
let lateName = ConnectionRig()
lateName.prefs.forget(cameraA.id); lateName.prefs.forget(cameraB.id)
lateName.wifi.joined = nil
var identityReads = 0
lateName.wifi.onCurrent = { identityReads += 1; return identityReads == 1 ? nil : cameraA }
lateName.start(target: nil); lateName.wait()
check(lateName.camera.calls == 2 && lateName.prefs.networks.first?.network.id == cameraA.id,
      "SSID appearing during connection is verified again and remembered")
let laterPermission = ConnectionRig()
laterPermission.prefs.forget(cameraA.id); laterPermission.prefs.forget(cameraB.id)
laterPermission.auth.allowed = false
laterPermission.start(target: nil); laterPermission.wait()
laterPermission.auth.allowed = true
laterPermission.connection.checkConnection()
waitFor("remember after authorization") { laterPermission.prefs.networks.first?.network.id == cameraA.id }
check(laterPermission.health.calls == 1 && laterPermission.events.last?["phase"] as? String == "remembered",
      "Late authorization verifies and remembers the still-connected camera without another CONNECT")
let lateForget = ConnectionRig()
lateForget.auth.allowed = false; lateForget.start(target: nil); lateForget.wait()
lateForget.connection.forget(cameraA.id)
waitFor("forget before late authorization") { !lateForget.prefs.networks.contains { $0.network.id == cameraA.id } }
lateForget.auth.allowed = true; lateForget.connection.checkConnection()
waitFor("verify after forgotten late identity") { lateForget.health.calls == 1 }
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
check(!lateForget.prefs.networks.contains { $0.network.id == cameraA.id }, "Late authorization cannot undo Forget")

firstManual.wifi.readyValue = false
firstManual.wifi.joined = nil
firstManual.connection.checkConnection()
waitFor("Wi-Fi lost") { !firstManual.connection.isConnected }
check(firstManual.events.last?["phase"] as? String == "disconnected" && firstManual.connection.nearby.isEmpty
      && firstManual.prefs.networks.count == 1 && firstManual.health.calls == 0
      && firstManual.connection.settingsValue()["currentName"] as? String == "",
      "Wi-Fi loss disconnects immediately, clears availability, and preserves known history")
let changedNetwork = ConnectionRig(); changedNetwork.start(target: cameraA.id); changedNetwork.wait()
changedNetwork.wifi.joined = cameraB; changedNetwork.connection.checkConnection()
waitFor("SSID changed") { !changedNetwork.connection.isConnected }
check(changedNetwork.health.calls == 0, "Changing SSID invalidates the old camera connection")
check(changedNetwork.connection.settingsValue()["currentName"] as? String == cameraB.name,
      "Disconnecting an old camera session retains the new current Wi-Fi name")
manual.health.result = .failure(appError("Camera is unavailable."))
manual.connection.checkConnection()
waitFor("camera lost without SSID permission") { !manual.connection.isConnected }
check(manual.events.last?["phase"] as? String == "disconnected", "Camera loss is detected even without SSID access")
let staleHealth = ConnectionRig(); staleHealth.start(target: cameraA.id); staleHealth.wait()
staleHealth.health.hold = true; staleHealth.connection.checkConnection()
waitFor("held health response") { staleHealth.health.pending.count == 1 }
let oldHealth = staleHealth.health.pending.removeFirst()
staleHealth.events = []; staleHealth.start("replacement", target: cameraA.id); staleHealth.wait()
oldHealth(.failure(appError("Obsolete disconnect")))
check(staleHealth.connection.isConnected && staleHealth.events.last?["phase"] as? String == "completed",
      "An obsolete health response cannot disconnect a newer camera session")
print("PASS: first/late SSID learning, permission recovery, Wi-Fi/camera loss, and stale health responses")

for value in ["{}", "{\"dirs\":[{}]}", "[{\"bad\":1}]"] {
    check((try? HTTPCameraVerification.photos(from: Data(value.utf8))) == nil, "Malformed photo list rejected")
}
check(try! HTTPCameraVerification.photos(from: Data("{\"dirs\":[]}".utf8)).isEmpty, "Valid empty directory list")
check(try! HTTPCameraVerification.photos(from: Data("[]".utf8)).isEmpty, "Valid empty flat list")
var httpResult: Result<[CameraPhoto], Error>?
let httpCamera = HTTPCameraVerification(base: fixtureURL)
httpCamera.verify { httpResult = $0 }
waitFor("real HTTP verification") { httpResult != nil }
check((try? httpResult!.get().isEmpty) == true, "Native HTTP ping and photo listing integrate with fixture")
var pingResult: Result<Void, Error>?
httpCamera.ping { pingResult = $0 }
waitFor("HTTP health ping") { pingResult != nil }
check((try? pingResult!.get()) != nil, "Native health check uses the local camera ping")

// Probe the same ad-hoc-signed bundle identity without requesting authorization or joining Wi-Fi.
check(Bundle.main.bundleIdentifier == "local.GRBrowser", "Platform probes use the actual bundled identity")
check(Bundle.main.object(forInfoDictionaryKey: "NSLocationUsageDescription") != nil, "Bundle includes contextual location usage")
let platformAuthorization = MacWiFiAuthorization()
let platformWiFi = MacWiFi()
let currentPlatformNetwork = platformWiFi.current()
check(currentPlatformNetwork == nil || !currentPlatformNetwork!.id.isEmpty, "Native SSID API handles unavailable identity")
if platformAuthorization.allowed {
    do {
        _ = try platformWiFi.scan()
        print("PASS: native authorized Wi-Fi discovery probe (no network changes)")
    } catch { print("LIMIT: live Wi-Fi discovery unavailable; fallback covered by fixtures") }
} else { print("PASS: native Wi-Fi permission fallback; live authorized discovery not exercised") }
let testKeychain = KeychainCameraCredentials(service: "local.GRBrowser.tests.\(UUID().uuidString)")
try! testKeychain.save("test-only-value", for: "test-only-account")
check(try! testKeychain.password(for: "test-only-account") == "test-only-value", "App-owned Keychain round trip")
try! testKeychain.remove("test-only-account")
check(try! testKeychain.password(for: "test-only-account") == nil, "App-owned Keychain deletion")

let settingsConfig = WKWebViewConfiguration()
settingsConfig.websiteDataStore = .nonPersistent()
settingsConfig.userContentController.add(appBridge, name: "app")
let settingsWeb = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 360), configuration: settingsConfig)
settingsWeb.loadHTMLString(SETTINGS_HTML, baseURL: nil)
waitFor("settings form loads independently") { !settingsWeb.isLoading }
func uiValue(_ function: String, _ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value)
    _ = js("\(function)(\(String(data: data, encoding: .utf8)!));")
    if function == "_settingsChanged" { _ = js("\(function)(\(String(data: data, encoding: .utf8)!));", on: settingsWeb) }
}
_ = js("_downloadEvent({id:downloadId,phase:'cancelled',message:'Reset'}); document.getElementById('settingsButton').focus();")
uiValue("_settingsChanged", ["folder": "/chosen/photos", "format": "separate",
    "networks": [["id": cameraA.id, "name": "GR_<camera>", "lastConnected": 100, "forgetting": false]],
    "available": [cameraA.id], "current": cameraA.id, "currentName": "GR_<camera>", "wifiConnected": true, "notice": ""])
jsCheck("!document.getElementById('networkSelect').hidden && document.getElementById('networkSelect').value === '' && document.getElementById('networkSelect').options.length === 1 && document.getElementById('networkSelect').selectedOptions[0].textContent === 'GR_<camera> (current)'", "Current network appears once and is selected by default")
_ = js("openSettings();")
waitFor("native settings request") { appBridge.requests.contains { $0["action"] as? String == "openSettings" } }
jsCheck("document.getElementById('settingsPanel') === null", "Settings is not an HTML modal inside the browser")
check(js("document.getElementById('folderPath').textContent === '/chosen/photos' && document.getElementById('exportFormat').value === 'separate'", on: settingsWeb) as? Bool == true, "Settings display authoritative values in their own page")
check(js("document.getElementById('knownNetworks').querySelector('img') === null && document.querySelector('.network-description').textContent.includes('GR_<camera>')", on: settingsWeb) as? Bool == true, "Network names render as text")
check(js("document.documentElement.scrollWidth <= 400 && document.getElementById('settingsClose').getAttribute('onclick').includes('closeSettings')", on: settingsWeb) as? Bool == true, "Settings form fits its narrow window and exposes Close")
_ = js("document.querySelector('#knownNetworks button').click(); document.getElementById('settingsClose').click();", on: settingsWeb)
waitFor("forget bridge") { appBridge.requests.contains { $0["action"] as? String == "forget" } }
waitFor("close native settings request") { appBridge.requests.contains { $0["action"] as? String == "closeSettings" } }
_ = js("_settingsClosed();")
jsCheck("document.activeElement.id === 'settingsButton'", "Closing Settings restores focus")
uiValue("_settingsChanged", ["folder": "/chosen/photos", "format": "zip", "networks": [], "available": [cameraA.id], "current": cameraA.id, "currentName": "GR_<camera>", "wifiConnected": true, "notice": ""])
jsCheck("!document.getElementById('networkSelect').hidden && document.getElementById('networkSelect').value === '' && document.getElementById('networkSelect').options.length === 1 && document.getElementById('networkSelect').selectedOptions[0].textContent === 'GR_<camera> (current)'", "Forget removes reconnect target while preserving the current Wi-Fi display")
_ = js("document.dispatchEvent(new KeyboardEvent('keydown',{key:',',metaKey:true,bubbles:true}));")
waitFor("Command-comma requests native Settings") { appBridge.requests.filter { $0["action"] as? String == "openSettings" }.count == 2 }
_ = js("_settingsClosed(); doConnect();")
jsCheck("connectionId !== null && document.getElementById('connBtn').disabled && Array.from(document.querySelectorAll('[data-download]')).every(b=>b.disabled)", "Connecting locks conflicting actions")
_ = js("_connectionEvent({id:'stale',phase:'completed',message:'wrong',photos:[]});")
jsCheck("connectionId !== null", "Stale connection UI event ignored")
_ = js("_connectionEvent({id:connectionId,phase:'completed',message:'0 photos',photos:[]});")
jsCheck("connectionId === null && !document.getElementById('connBtn').disabled", "Connection result unlocks controls")
_ = js("doConnect(); _connectionEvent({id:connectionId,phase:'completed',message:'1 photo',photos:[{dir:'DCIM',file:'one.JPG'}]}); selAll(); openLb(0);")
jsCheck("photos.length === 1 && document.getElementById('dot').classList.contains('connected')", "Verified connection displays its photos")
_ = js("_connectionEvent({id:connectedId,phase:'disconnected',message:'Camera disconnected.'});")
jsCheck("connectedId === null && photos.length === 0 && sel.size === 0 && !document.getElementById('dot').classList.contains('connected') && document.getElementById('grid').children.length === 0 && !document.getElementById('lb').classList.contains('open') && document.getElementById('selAllBtn').disabled && document.getElementById('dlBtn').disabled && document.getElementById('status').textContent === 'Camera disconnected.'", "Disconnect clears photos, selection, preview, status, and download controls")
_ = js("doConnect(); _connectionEvent({id:connectionId,phase:'completed',message:'0 photos',photos:[],warning:'Allow Location Services to remember Wi-Fi.'});")
jsCheck("document.getElementById('status').textContent.includes('Allow Location Services')", "Missing Wi-Fi identity is explained beside connection status")
_ = js("_connectionEvent({id:connectedId,phase:'remembered',message:'0 photos'});")
jsCheck("document.getElementById('status').textContent === '0 photos'", "Late network learning clears the missing-identity warning")
_ = js("const previousSession = connectedId; doConnect(); _connectionEvent({id:previousSession,phase:'disconnected',message:'Stale loss'});")
jsCheck("connectionId !== null && document.getElementById('status').textContent !== 'Stale loss'", "Old disconnect events cannot replace a new connection")
_ = js("_connectionEvent({id:connectionId,phase:'completed',message:'0 photos',photos:[]});")
uiValue("_settingsChanged", ["folder": "", "format": "zip", "networks": [
    ["id": cameraB.id, "name": "GR_B", "lastConnected": 200, "forgetting": false],
    ["id": cameraA.id, "name": "GR_A", "lastConnected": 100, "forgetting": false]],
    "available": [cameraA.id, cameraB.id], "current": cameraA.id, "currentName": cameraA.name, "wifiConnected": true, "notice": ""])
_ = js("document.getElementById('networkSelect').value='';")
uiValue("_settingsChanged", ["folder": "", "format": "zip", "networks": [
    ["id": cameraB.id, "name": "GR_B", "lastConnected": 200, "forgetting": false],
    ["id": cameraA.id, "name": "GR_A", "lastConnected": 100, "forgetting": false]],
    "available": [cameraA.id, cameraB.id], "current": cameraA.id, "currentName": cameraA.name, "wifiConnected": true, "notice": ""])
jsCheck("document.getElementById('networkSelect').value === '' && document.getElementById('networkSelect').options.length === 2 && document.getElementById('networkSelect').selectedOptions[0].textContent === 'GR_A (current)'", "Selector defaults to the current network rather than silently targeting another camera")
_ = js("document.getElementById('networkSelect').value='\(cameraB.id)'; document.getElementById('networkSelect').dispatchEvent(new Event('change'));")
jsCheck("document.getElementById('networkSelect').title === 'GR_B'", "Selector tooltip follows an explicitly selected target immediately")
uiValue("_settingsChanged", ["folder": "", "format": "zip", "networks": [
    ["id": cameraB.id, "name": cameraB.name, "lastConnected": 200, "forgetting": false]],
    "available": [cameraB.id], "current": cameraA.id, "currentName": cameraA.name, "wifiConnected": true, "notice": ""])
check(js("document.getElementById('networkSelect').value") as? String == cameraB.id, "Explicit camera selection survives updates while available")
_ = js("document.getElementById('networkSelect').value=''; document.getElementById('networkSelect').dispatchEvent(new Event('change'));")
uiValue("_settingsChanged", ["folder": "", "format": "zip", "networks": [
    ["id": cameraB.id, "name": "GR_B", "lastConnected": 200, "forgetting": false]],
    "available": [cameraB.id], "current": "", "currentName": "", "wifiConnected": false, "notice": ""])
jsCheck("document.getElementById('networkSelect').value === ''", "Explicit Current Wi-Fi choice survives discovery updates")
jsCheck("document.getElementById('networkSelect').selectedOptions[0].textContent === 'No Wi-Fi connection'", "Disconnected Wi-Fi is explicit in the always-visible selector")
uiValue("_settingsChanged", ["folder": "", "format": "zip", "networks": [], "available": [], "current": "", "currentName": "", "wifiConnected": true, "notice": ""])
jsCheck("!document.getElementById('networkSelect').hidden && document.getElementById('networkSelect').selectedOptions[0].textContent === 'Current Wi-Fi — name unavailable'", "Unavailable SSIDs remain explicit without hiding the selector")
print("PASS: Settings UI, keyboard/focus, safe labels, dropdown removal, layout, and connection locks")
// Exercise the actual bridge and downloader together, with isolated settings and local HTTP.
let livePrefs = testPreferences()
livePrefs.remember(cameraB, at: Date(timeIntervalSince1970: 1))
let liveOutput = testRoot.appendingPathComponent("bridge-output")
let liveStaging = testRoot.appendingPathComponent("bridge-staging")
try! fm.createDirectory(at: liveOutput, withIntermediateDirectories: true)
try! fm.createDirectory(at: liveStaging, withIntermediateDirectories: true)
try! livePrefs.setFolder(liveOutput)
let liveDownload = DownloadHandler(preferences: livePrefs, cameraBase: fixtureURL, temporaryDirectory: liveStaging)
let liveAuthorization = FakeAuthorization()
liveAuthorization.allowed = false; liveAuthorization.hold = true
let liveWiFi = FakeWiFi()
liveWiFi.networks = []; liveWiFi.joined = homeNetwork
let liveClock = TestClock()
let liveConnection = CameraConnection(preferences: livePrefs, wifi: liveWiFi, authorization: liveAuthorization,
                                      credentials: FakeCredentials(), savedCredentials: FakeCredentials(),
                                      camera: FakeCamera(), health: FakeCamera(),
                                      now: { liveClock.time }, later: liveClock.schedule)
let liveController = AppController(preferences: livePrefs, download: liveDownload, connection: liveConnection)
let liveConfig = WKWebViewConfiguration()
liveConfig.websiteDataStore = .nonPersistent()
liveConfig.userContentController.add(liveController, name: "app")
liveConfig.userContentController.add(liveDownload, name: "download")
let liveWeb = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 360), configuration: liveConfig)
liveController.webView = liveWeb
liveDownload.webView = liveWeb
liveWeb.loadHTMLString(APP_HTML, baseURL: nil)
waitFor("native bridge page") { !liveWeb.isLoading }
waitFor("startup permission request") { liveAuthorization.requests == 1 && liveAuthorization.pending.count == 1 }
check(js("appSettings.discoveryAllowed", on: liveWeb) as? Bool == false, "Pending discovery authorization is reflected in native settings state")
liveAuthorization.allowed = true; liveAuthorization.hold = false
liveAuthorization.pending.removeFirst()(true)
waitFor("current name after startup authorization") { liveConnection.settingsValue()["currentName"] as? String == homeNetwork.name }
waitFor("permission reflected in Settings") {
    js("appSettings.discoveryAllowed", on: liveWeb) as? Bool == true
}
check(liveWiFi.scans == 1 && liveConnection.nearby.isEmpty
      && js("!document.getElementById('networkSelect').hidden && document.getElementById('networkSelect').options.length === 1 && document.getElementById('networkSelect').selectedOptions[0].textContent === 'Home <& Wi-Fi> (current)'", on: liveWeb) as? Bool == true,
      "Startup with camera off still shows the current unrelated Wi-Fi name safely")
liveWiFi.networks = [cameraB]; liveClock.advance(10); liveConnection.poll()
waitFor("late camera option reaches WebKit") {
    js("!document.getElementById('networkSelect').hidden && document.getElementById('networkSelect').options.length === 2", on: liveWeb) as? Bool == true
}
check(js("document.getElementById('networkSelect').value", on: liveWeb) as? String == ""
      && liveWiFi.joins.isEmpty && liveAuthorization.requests == 1,
      "Late discovery automatically adds the remembered camera without restart, association, or another prompt")
_ = js("document.getElementById('networkSelect').value='\(cameraB.id)';", on: liveWeb)
liveWiFi.networks = []; liveClock.advance(10); liveConnection.poll()
waitFor("lost camera removed from actual selector") {
    js("document.getElementById('networkSelect').options.length === 1 && document.getElementById('networkSelect').value === '' && document.getElementById('networkSelect').selectedOptions[0].textContent === 'Home <& Wi-Fi> (current)'", on: liveWeb) as? Bool == true
}
check(livePrefs.networks.count == 1 && liveWiFi.joins.isEmpty, "Camera disappearance removes its option but preserves history and the current connection")
let browserWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 360),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
browserWindow.isReleasedWhenClosed = false
browserWindow.contentView = liveWeb
browserWindow.makeKeyAndOrderFront(nil)
func exerciseSettings(_ inspect: @escaping (SettingsWindowController) -> Void) {
    var inspected = false
    let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
        guard !inspected, let controller = liveController.settingsController,
              NSApplication.shared.modalWindow === controller.window, !controller.webView.isLoading else { return }
        inspected = true
        inspect(controller)
    }
    RunLoop.main.add(timer, forMode: .modalPanel)
    liveController.showSettings()
    waitFor("native modal settings interaction") { inspected && NSApplication.shared.modalWindow == nil }
    timer.invalidate()
    check(browserWindow.isVisible && liveController.settingsController?.window?.isVisible == false,
          "Closing Settings leaves the browser open")
}
exerciseSettings { controller in
    check(controller.window?.styleMask.contains(.titled) == true
          && controller.window?.standardWindowButton(.closeButton)?.isEnabled == true
          && controller.window?.standardWindowButton(.closeButton)?.isHidden == false, "Settings has native window chrome and a visible close button")
    check(js("document.getElementById('exportFormat').value", on: controller.webView) as? String == "zip", "Native Settings starts from stored preferences")
    _ = js("document.getElementById('exportFormat').value='separate'; document.getElementById('exportFormat').dispatchEvent(new Event('change'));", on: controller.webView)
    waitFor("format updates during native modal loop") { livePrefs.format == .separate }
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                windowNumber: controller.window!.windowNumber, context: nil,
                                characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
    check(controller.window!.performKeyEquivalent(with: event), "Native Settings handles Command-W")
}
let originalSettings = liveController.settingsController
exerciseSettings { controller in
    check(controller === originalSettings && js("document.getElementById('exportFormat').value", on: controller.webView) as? String == "separate",
          "Reopening reuses Settings and retains the saved format")
    controller.window?.standardWindowButton(.closeButton)?.performClick(nil)
}
exerciseSettings { controller in controller.window?.cancelOperation(nil) }
exerciseSettings { controller in
    let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 100),
                        styleMask: [.titled], backing: .buffered, defer: false)
    sheet.worksWhenModal = true
    controller.window!.beginSheet(sheet)
    check(controller.windowShouldClose(controller.window!) == false,
          "A folder-picker sheet prevents closing its Settings parent")
    controller.window!.endSheet(sheet)
    sheet.orderOut(nil)
    waitFor("settings child sheet ends") { controller.window?.attachedSheet == nil }
    _ = js("document.getElementById('settingsClose').click();", on: controller.webView)
}
print("PASS: native Settings modal, visible title-bar close, Command-W, Escape, child sheet, reopening, and preference updates")
_ = js("photos=[{dir:'DCIM',file:'live-one.JPG'},{dir:'DCIM',file:'live-two.JPG'}]; selAll(); dlSelected();", on: liveWeb)
waitFor("download starts before opening Settings") { liveDownload.isDownloading }
exerciseSettings { controller in
    waitFor("native export continues with Settings modal open") {
        !liveDownload.isDownloading && (try? fm.contentsOfDirectory(atPath: liveOutput.path).count) == 2
    }
    check(js("downloadId === null", on: liveWeb) as? Bool == true, "Browser receives download completion while Settings is modal")
    controller.window?.performClose(nil)
}
check(js("downloadId === null && document.getElementById('downloadStatus').hidden", on: liveWeb) as? Bool == true,
      "Native terminal event restores WebKit state")
check((try? Data(contentsOf: liveOutput.appendingPathComponent("live-one.JPG")).count) == 2_097_152,
      "Actual settings bridge and downloader publish original photos")
print("PASS: end-to-end WebKit settings bridge, native preferences, direct export, and terminal events")
browserWindow.close()
print("All settings, reconnect, and download tests passed.")


for domain in preferenceDomains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
