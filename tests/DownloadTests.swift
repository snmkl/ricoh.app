import Cocoa
import CoreWLAN
import CoreLocation
import Security
import Darwin

func runDownloadTests() {
    let known = runDownload("known-length")
    check(known.events.contains { event in
        guard let fraction = event.fraction else { return false }
        return fraction > 0 && fraction < 1 && event.completed == 0
    }, "Known-length transfer advances before completion")
    check(!known.events.contains { $0.phase.rawValue == "awaiting-save" } && known.chooseCount == 0, "Configured destination skips save dialogs")
    check(known.events.contains { $0.phase.rawValue == "saving" }, "Saving stage emitted")
    check(try! Data(contentsOf: known.saved.first!).count == 2_097_152, "Single photo output is complete")

    let unknown = runDownload("unknown-length", files: ["DCIM/unknown.JPG"])
    check(unknown.events.contains { $0.phase.rawValue == "downloading" && $0.fraction == nil },
          "Unknown length has indeterminate activity")
    check(!unknown.events.contains { ($0.completed == 0) && $0.fraction != nil },
          "Unknown length never fabricates a transfer percentage")

    let batch = runDownload("batch", files: ["DCIM/slow.JPG", "OTHER/second.JPG"])
    check(batch.events.contains { $0.completed == 1 && $0.total == 2 }, "Batch file counts advance")
    check(batch.events.contains { event in
        guard let fraction = event.fraction else { return false }
        return event.completed == 1 && fraction > 0.5 && fraction < 1
    }, "Batch percentage weights completed and active files")
    check(batch.events.contains { $0.phase.rawValue == "archiving" && $0.fraction == nil }, "Archive is a separate indeterminate stage")
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
        check(failed.terminal?.completed == 1, "Only successful files count as complete")
        failed.startDownload(id: "retry-\(file)", files: ["DCIM/slow.JPG"])
        waitFor("retry after \(file)") { failed.events.filter { terminalPhases.contains($0.phase.rawValue) }.count == 2 }
        check(failed.terminal?.phase.rawValue == "completed", "Fresh download works after failure")
    }

    let quotedName = "DCIM/photo'\"\\name.JPG"
    let quoted = runDownload("quoted-name", files: [quotedName])
    check(quoted.events.contains { $0.filename == (quotedName as NSString).lastPathComponent },
          "Typed events preserve quotes and backslashes")

    let duplicates = runDownload("duplicate-requests", files: ["DCIM/slow.JPG"], setup: { handler, _ in
        handler.onObservedEvent = { event in
            if !terminalPhases.contains(event.phase.rawValue) {
                handler.startDownload(id: "duplicate", files: ["DCIM/slow.JPG"])
            }
        }
        handler.onChoose = { handler.startDownload(id: "duplicate-at-save", files: ["DCIM/slow.JPG"]) }
    })
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    check(duplicates.events.allSatisfy { $0.id == "duplicate-requests" } && duplicates.chooseCount == 0,
          "Native guard rejects duplicate requests including at save time")

    _ = runDownload("save-cancelled", expected: "cancelled", cancel: true)
    _ = runDownload("save-write-failed", expected: "failed", setup: { handler, _ in
        handler.failAfter = 0
    })
    _ = runDownload("staging-failed", expected: "failed", setup: { handler, staging in
        var injected = false
        handler.onObservedEvent = { event in
            if !injected && event.phase.rawValue == "downloading" {
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
}
