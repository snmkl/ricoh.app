import Cocoa
import CoreWLAN
import CoreLocation
import Security
import Darwin

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
final class ObservedDownload: DownloadService, @unchecked Sendable {
    var events: [DownloadEvent] = []
    var destination: URL?
    var saved: [URL] = []
    var failAfter: Int?
    var onPublish: (() -> Void)?
    override func publishFile(_ source: URL, in directory: URL) throws -> URL {
        onPublish?()
        if failAfter == saved.count { throw appError("Injected destination failure") }
        let result = try super.publishFile(source, in: directory)
        saved.append(result)
        return result
    }
    var chooseCount = 0
    var onObservedEvent: ((DownloadEvent) -> Void)?
    var onChoose: (() -> Void)?

    override func deliverEvent(_ event: DownloadEvent) {
        super.deliverEvent(event)
        check(Thread.isMainThread, "Events arrive on the main thread")
        events.append(event)
        onObservedEvent?(event)
    }

    override func chooseDirectory(completion: @escaping (URL?) -> Void) {
        check(Thread.isMainThread, "Save chooser runs on the main thread")
        chooseCount += 1
        onChoose?()
        completion(destination)
    }

    var terminal: DownloadEvent? { events.last { terminalPhases.contains($0.phase.rawValue) } }
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
    check(handler.terminal?.phase.rawValue == expected, "\(name): expected \(expected), got \(String(describing: handler.terminal))")
    check((try! fm.contentsOfDirectory(atPath: staging.path)).isEmpty, "\(name): removes temporary files")
    print("PASS: \(name)")
    return handler
}


let cameraA = CameraNetwork(name: "GR_A")
let cameraB = CameraNetwork(name: "GR_B")
let app = NSApplication.shared
let homeNetwork = CameraNetwork(name: "Home <& Wi-Fi>")
