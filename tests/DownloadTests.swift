// Compiled with the app's actual source (excluding its AppDelegate and entry point).
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func waitFor(_ message: String, timeout: TimeInterval = 15, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    check(condition(), "Timeout: \(message)")
}

let fixtureURL = URL(string: CommandLine.arguments[1])!
let testRoot = URL(fileURLWithPath: CommandLine.arguments[2])
let fm = FileManager.default
let terminalPhases = ["completed", "failed", "cancelled"]

var preferenceDomains: [String] = []
func testPreferences() -> AppPreferences {
    let name = "GRBrowser.tests.\(UUID().uuidString)"
    preferenceDomains.append(name)
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return AppPreferences(defaults: defaults)
}
final class AppBridge: NSObject, WKScriptMessageHandler {
    var requests: [[String: Any]] = []
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { requests.append(body) }
    }
}

final class ObservedDownload: DownloadHandler, @unchecked Sendable {
    var events: [[String: Any]] = []
    var destination: URL?
    var saved: [URL] = []
    var failAfter: Int?
    override func publishFile(_ source: URL, in directory: URL) throws -> URL {
        if failAfter == saved.count { throw appError("Injected destination failure") }
        let result = try super.publishFile(source, in: directory)
        saved.append(result)
        return result
    }
    var chooseCount = 0
    var onEvent: (([String: Any]) -> Void)?
    var onChoose: (() -> Void)?

    override func deliverEvent(json: String) {
        check(Thread.isMainThread, "Events arrive on the main thread")
        let event = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        events.append(event)
        onEvent?(event)
    }

    override func chooseDirectory(completion: @escaping (URL?) -> Void) {
        check(Thread.isMainThread, "Save chooser runs on the main thread")
        chooseCount += 1
        onChoose?()
        completion(destination)
    }

    var terminal: [String: Any]? { events.last { terminalPhases.contains($0["phase"] as? String ?? "") } }
}

func runDownload(_ name: String, files: [String] = ["DCIM/slow.JPG"],
                 archive: URL = URL(fileURLWithPath: "/usr/bin/ditto"),
                 expected: String = "completed", cancel: Bool = false,
                 setup: ((ObservedDownload, URL) -> Void)? = nil) -> ObservedDownload {
    let root = testRoot.appendingPathComponent(name)
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    let staging = root.appendingPathComponent("staging")
    try! fm.createDirectory(at: staging, withIntermediateDirectories: true)
    let preferences = testPreferences()
    let output = root.appendingPathComponent("output")
    try! fm.createDirectory(at: output, withIntermediateDirectories: true)
    let handler = ObservedDownload(preferences: preferences, cameraBase: fixtureURL, temporaryDirectory: staging, archiveExecutable: archive)
    handler.destination = cancel ? nil : output
    if !cancel { try! preferences.setFolder(output) }
    setup?(handler, staging)
    handler.startDownload(id: name, files: files)
    waitFor(name) { handler.terminal != nil }
    check(handler.terminal?["phase"] as? String == expected, "\(name): expected \(expected), got \(handler.terminal ?? [:])")
    check((try! fm.contentsOfDirectory(atPath: staging.path)).isEmpty, "\(name): removes temporary files")
    print("PASS: \(name)")
    return handler
}

let known = runDownload("known-length")
check(known.events.contains { event in
    guard let fraction = event["fraction"] as? Double else { return false }
    return fraction > 0 && fraction < 1 && event["completed"] as? Int == 0
}, "Known-length transfer advances before completion")
check(!known.events.contains { $0["phase"] as? String == "awaiting-save" } && known.chooseCount == 0, "Configured destination skips save dialogs")
check(known.events.contains { $0["phase"] as? String == "saving" }, "Saving stage emitted")
check(try! Data(contentsOf: known.saved.first!).count == 2_097_152, "Single photo output is complete")

let unknown = runDownload("unknown-length", files: ["DCIM/unknown.JPG"])
check(unknown.events.contains { $0["phase"] as? String == "downloading" && $0["fraction"] == nil },
      "Unknown length has indeterminate activity")
check(!unknown.events.contains { ($0["completed"] as? Int == 0) && $0["fraction"] != nil },
      "Unknown length never fabricates a transfer percentage")

let batch = runDownload("batch", files: ["DCIM/slow.JPG", "OTHER/second.JPG"])
check(batch.events.contains { $0["completed"] as? Int == 1 && $0["total"] as? Int == 2 }, "Batch file counts advance")
check(batch.events.contains { event in
    guard let fraction = event["fraction"] as? Double else { return false }
    return event["completed"] as? Int == 1 && fraction > 0.5 && fraction < 1
}, "Batch percentage weights completed and active files")
check(batch.events.contains { $0["phase"] as? String == "archiving" && $0["fraction"] == nil }, "Archive is a separate indeterminate stage")
let unzip = Process()
unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
unzip.arguments = ["-Z1", batch.saved.first!.path]
let listing = Pipe()
unzip.standardOutput = listing
try! unzip.run()
let entries = String(data: listing.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
unzip.waitUntilExit()
check(unzip.terminationStatus == 0 && entries.contains("Photos/DCIM/slow.JPG") && entries.contains("Photos/OTHER/second.JPG"),
      "ZIP contains both requested photos")

for file in ["missing.JPG", "interrupted.JPG"] {
    let failed = runDownload(file, files: ["DCIM/slow.JPG", "DCIM/\(file)"], expected: "failed")
    check(failed.chooseCount == 0 && failed.saved.isEmpty, "No partial ZIP is offered")
    check(failed.terminal?["completed"] as? Int == 1, "Only successful files count as complete")
    failed.startDownload(id: "retry-\(file)", files: ["DCIM/slow.JPG"])
    waitFor("retry after \(file)") { failed.events.filter { terminalPhases.contains($0["phase"] as? String ?? "") }.count == 2 }
    check(failed.terminal?["phase"] as? String == "completed", "Fresh download works after failure")
}

let quotedName = "DCIM/photo'\"\\name.JPG"
let quoted = runDownload("quoted-name", files: [quotedName])
check(quoted.events.contains { $0["filename"] as? String == (quotedName as NSString).lastPathComponent },
      "JSON serialization preserves quotes and backslashes")

let duplicates = runDownload("duplicate-requests", files: ["DCIM/slow.JPG"], setup: { handler, _ in
    handler.onEvent = { event in
        if !terminalPhases.contains(event["phase"] as? String ?? "") {
            handler.startDownload(id: "duplicate", files: ["DCIM/slow.JPG"])
        }
    }
    handler.onChoose = { handler.startDownload(id: "duplicate-at-save", files: ["DCIM/slow.JPG"]) }
})
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
check(duplicates.events.allSatisfy { $0["id"] as? String == "duplicate-requests" } && duplicates.chooseCount == 0,
      "Native guard rejects duplicate requests including at save time")

_ = runDownload("save-cancelled", expected: "cancelled", cancel: true)
_ = runDownload("save-write-failed", expected: "failed", setup: { handler, _ in
    handler.failAfter = 0
})
_ = runDownload("staging-failed", expected: "failed", setup: { handler, staging in
    var injected = false
    handler.onEvent = { event in
        if !injected && event["phase"] as? String == "downloading" {
            injected = true
            let jobDir = try! fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).first!
            let photos = jobDir.appendingPathComponent("Photos")
            try! fm.removeItem(at: photos)
            try! Data("blocks staging".utf8).write(to: photos)
        }
    }
})
for (name, executable) in [("archive-launch-failed", "/no/such/ditto"),
                           ("archive-exit-failed", "/usr/bin/false"),
                           ("archive-output-missing", "/usr/bin/true")] {
    let failed = runDownload(name, files: ["DCIM/one.JPG", "DCIM/two.JPG"],
                             archive: URL(fileURLWithPath: executable), expected: "failed")
    check(failed.chooseCount == 0, "Archive errors never offer a save dialog")
}
let badArchive = testRoot.appendingPathComponent("bad-archive.sh")
try! Data("#!/bin/sh\nprintf broken > \"$5\"\n".utf8).write(to: badArchive)
try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: badArchive.path)
_ = runDownload("archive-output-invalid", files: ["DCIM/one.JPG", "DCIM/two.JPG"], archive: badArchive, expected: "failed")

// Exercise the embedded interface in a real WKWebView, without camera hardware or a save dialog.
final class DownloadBridge: NSObject, WKScriptMessageHandler {
    var requests: [[String: Any]] = []
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        requests.append(try! JSONSerialization.jsonObject(with: Data((message.body as! String).utf8)) as! [String: Any])
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let bridge = DownloadBridge()
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
config.userContentController.add(bridge, name: "download")
let appBridge = AppBridge()
config.userContentController.add(appBridge, name: "app")
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 360), configuration: config)
web.loadHTMLString(APP_HTML, baseURL: nil)
var ready = false
waitFor("WebKit loads UI") {
    if !web.isLoading { ready = true }
    return ready
}
func js(_ script: String, on target: WKWebView? = nil) -> Any? {
    var done = false
    var result: Any?
    var problem: Error?
    (target ?? web).evaluateJavaScript(script) { value, error in result = value; problem = error; done = true }
    waitFor("JavaScript evaluation") { done }
    check(problem == nil, "JavaScript: \(problem.map { ($0 as NSError).userInfo.description } ?? "") in \(script.prefix(180))")
    return result
}
func jsCheck(_ expression: String, _ message: String) {
    check(js(expression) as? Bool == true, message)
}
_ = js("photos = [{dir:'DCIM',file:'one.JPG'}, {dir:'DCIM',file:'two.JPG'}]; sel.add(key(photos[0])); updSel(); openLb(0); dlCurrent();")
waitFor("Preview download request") { bridge.requests.count == 1 }
jsCheck("!document.getElementById('downloadStatus').hidden && document.getElementById('lb').classList.contains('open')", "Preview shows progress immediately")
jsCheck("Array.from(document.querySelectorAll('[data-download]')).every(b => b.disabled)", "All download actions disabled")
_ = js("clearSel(); closeLb(); openLb(1); dlCurrent();")
jsCheck("!document.getElementById('downloadStatus').hidden && Array.from(document.querySelectorAll('[data-download]')).every(b => b.disabled)", "Browsing/selection keeps progress visible and downloads disabled")
check(bridge.requests.count == 1, "Duplicate JS action does not post another request")
_ = js("_downloadEvent({id:'stale',phase:'completed',message:'wrong'});")
jsCheck("downloadId !== null && !document.getElementById('downloadStatus').hidden", "Stale terminal event ignored")
_ = js("_downloadEvent({id:downloadId,phase:'downloading',completed:0,total:2,filename:'one.JPG',fraction:0.25});")
jsCheck("document.getElementById('downloadProgress').value === 0.25 && document.getElementById('downloadPercent').textContent === 'Transfer 25%'", "Measured percentage renders")
_ = js("_downloadEvent({id:downloadId,phase:'downloading',completed:0,total:2,filename:'one.JPG'});")
jsCheck("!document.getElementById('downloadProgress').hasAttribute('value') && document.getElementById('downloadPercent').textContent === ''", "Unknown length removes numeric progress")
_ = js("_downloadEvent({id:downloadId,phase:'archiving',completed:2,total:2});")
jsCheck("document.getElementById('downloadStage').textContent === 'Creating ZIP…' && !document.getElementById('downloadProgress').hasAttribute('value')", "Archive phase remains active")
jsCheck("(() => { const p=document.getElementById('downloadStatus'), r=p.getBoundingClientRect(); return r.left>=0 && r.right<=480 && r.top>=0 && r.bottom<=284 && Number(getComputedStyle(p).zIndex)>Number(getComputedStyle(document.getElementById('lb')).zIndex); })()", "Progress fits minimum window above preview and selection controls")
jsCheck("document.getElementById('downloadStage').getAttribute('aria-live') === 'polite' && document.getElementById('downloadProgress').getAttribute('aria-label') !== null", "Progress has accessible status and label")
for phase in ["cancelled", "failed", "completed"] {
    _ = js("_downloadEvent({id:downloadId,phase:'\(phase)',message:'Outcome'});")
    jsCheck("downloadId === null && document.getElementById('downloadStatus').hidden && !document.querySelector('[data-download=current]').disabled && document.querySelector('[data-download=selection]').disabled", "\(phase) resets UI and restores eligible controls")
    _ = js("sel.add(key(photos[0])); updSel(); dlSelected();")
    waitFor("new batch request") { bridge.requests.count >= 2 }
    _ = js("clearSel();")
}
jsCheck("document.getElementById('downloadCounts').textContent === '0/1 files'", "New operation starts with fresh counts")
print("PASS: WebKit UI, minimum layout, accessibility, stale events, and terminal recovery")
