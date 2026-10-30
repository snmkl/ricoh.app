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
    let cancelled = runDownload("transfer-cancelled", files: ["DCIM/slow.JPG", "OTHER/second.JPG"],
                                expected: "cancelled", setup: { handler, _ in
        handler.onObservedEvent = { event in
            if event.phase == .downloading, let fraction = event.fraction, fraction > 0 {
                handler.cancelDownload(id: event.id)
            }
        }
    })
    check(cancelled.saved.isEmpty && cancelled.terminal?.completed == 0 && !cancelled.isDownloading,
          "Cancelling an active transfer publishes nothing and releases admission")
    cancelled.onObservedEvent = nil
    cancelled.startDownload(id: "retry-after-cancel", files: ["DCIM/one.JPG"])
    cancelled.cancelDownload(id: "transfer-cancelled")
    waitFor("retry after cancellation") { cancelled.terminal?.id == "retry-after-cancel" }
    check(cancelled.terminal?.phase == .completed && cancelled.saved.count == 1,
          "A fresh download succeeds and ignores cancellation for an old request")
    check(cancelled.events.filter { $0.id == "transfer-cancelled" && $0.phase.terminal }.count == 1,
          "Late URLSession callbacks cannot emit another cancellation outcome")
    _ = runDownload("immediately-cancelled", expected: "cancelled", setup: { handler, _ in
        handler.onObservedEvent = { event in
            if event.phase == .preparing { handler.cancelDownload(id: event.id) }
        }
    })
    let slowArchive = testRoot.appendingPathComponent("slow-archive.sh")
    try! Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: slowArchive)
    try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slowArchive.path)
    let archiveStarted = Date()
    let archiveCancelled = runDownload("archive-cancelled", files: ["DCIM/one.JPG", "DCIM/two.JPG"],
                                       archive: slowArchive, expected: "cancelled", setup: { handler, _ in
        handler.onObservedEvent = { event in
            if event.phase == .archiving { handler.cancelDownload(id: event.id) }
        }
    })
    check(archiveCancelled.saved.isEmpty && Date().timeIntervalSince(archiveStarted) < 8,
          "Cancellation stops a running archive and cleans staging before releasing admission")
    let savingCancelled = runDownload("saving-cancelled", files: ["DCIM/one.JPG", "DCIM/two.JPG"],
                                      expected: "cancelled", setup: { handler, _ in
        handler.preferences.setFormat(.separate)
        handler.onPublish = {
            if handler.saved.count == 1 {
                DispatchQueue.main.sync { handler.cancelDownload(id: "saving-cancelled") }
            }
        }
    })
    check(savingCancelled.saved.count == 1
          && (try! fm.contentsOfDirectory(atPath: savingCancelled.destination!.path)).count == 1,
          "Cancelling publication preserves saved photos and stops remaining files")
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
