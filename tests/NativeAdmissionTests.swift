import Cocoa

@MainActor func runNativeAdmissionTests() {
    let rig = BluetoothRig()
    let download = DownloadService(preferences: rig.prefs, cameraBase: fixtureURL, temporaryDirectory: testRoot)
    let controller = AppController(preferences: rig.prefs, download: download, connection: rig.connection)
    let model = controller.model
    model.selectTarget(.network("not-a-known-network"))
    check(model.target == .currentWiFi, "Presentation does not install a target rejected by the service")
    model.selectTarget(.bluetooth(rig.id))
    rig.connection.forgetBluetooth(rig.id.uuidString)
    check(model.target == .currentWiFi, "Independent Forget resets native preferred Bluetooth target")
    rig.camera.result = .success([CameraPhoto(dir: "DCIM", file: "one.JPG"),
        CameraPhoto(dir: "OTHER", file: "two.JPG"), CameraPhoto(dir: "DCIM", file: "unknown.JPG")])
    model.primaryAction()
    waitFor("admission fixture verified library") { rig.connection.isConnected }
    var picked: ((URL?) -> Void)?
    var pickers = 0
    controller.folderChooser = { _, _, done in pickers += 1; picked = done }
    let files = ["DCIM/one.JPG", "OTHER/two.JPG"]
    model.requestDownload(files)
    waitFor("native presentation destination reservation") { picked != nil }
    check(download.isDownloading && !model.canDownload && !model.primaryEnabled, "Native destination selection reserves lifecycle admission")
    model.requestDownload(files)
    download.startDownload(id: "bypass-download", files: files)
    rig.connection.connect(id: "bypass-connect", target: nil as String?)
    check(pickers == 1 && !rig.connection.isConnecting, "Service rejects duplicate requests and connection bypass while picker waits")
    rig.prefs.setFormat(.separate)
    let output = testRoot.appendingPathComponent("native-picker-output")
    try! fm.createDirectory(at: output, withIntermediateDirectories: true)
    picked?(output)
    waitFor("native picker snapshot export") { !download.isDownloading }
    let saved = try! fm.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
    check(saved.count == 1 && saved[0].pathExtension == "zip", "Native accepted batch freezes format before picker even when Settings changes")
    let old = download.lastEvent!
    model.requestDownload(["DCIM/unknown.JPG"])
    waitFor("native unknown-length progress") { model.progress?.phase == .downloading }
    let current = model.progress!.id
    model.receive(old)
    check(model.progress?.id == current && model.progress?.fraction == nil, "Old terminal events cannot alter native indeterminate progress")
    waitFor("native unknown-length completion") { !download.isDownloading }
    check(model.progress == nil && model.status.hasPrefix("Saved:"), "Native terminal recovery restores controls")
    print("PASS: native picker admission, independent target Forget, captured format, indeterminate progress and stale terminal rejection")
}
