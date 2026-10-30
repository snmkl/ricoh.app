import Foundation
import Darwin

// Sequential original transfers and exclusive publication. Presentation supplies the folder chooser.

class DownloadService: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var folderChooser: (@escaping (URL?) -> Void) -> Void = { $0(nil) }
    var onEvent: ((DownloadEvent) -> Void)?
    private(set) var lastEvent: DownloadEvent?
    let preferences: AppPreferences
    var canStart: () -> Bool = { true }
    var isDownloading: Bool { activeRequestID != nil }
    // Main-thread admission guard also rejects requests queued during a disk write.
    private var activeRequestID: String?
    private var cancellation: Progress?

    // Operation state and delegate callbacks are confined to this serial queue.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let cameraBase: URL
    private let temporaryDirectory: URL
    private let archiveExecutable: URL
    private var session: URLSession?
    private var operation: DownloadOperation?
    private var currentTask: URLSessionDownloadTask?

    private final class DownloadOperation {
        let id: String
        let files: [String]
        let directory: URL
        let format: ExportFormat
        let cancellation: Progress
        var destination: URL?
        var stagedFiles: [URL] = []
        var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
        var completed = 0
        var lastProgressTime = Date.distantPast
        var stagedFile: URL?
        var filename: String { (files[min(completed, files.count - 1)] as NSString).lastPathComponent }

        init(id: String, files: [String], directory: URL, format: ExportFormat, cancellation: Progress) {
            self.id = id
            self.files = files
            self.directory = directory
            self.format = format
            self.cancellation = cancellation
        }
    }

    init(preferences: AppPreferences = AppPreferences(), cameraBase: URL = URL(string: CAMERA_BASE)!,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         archiveExecutable: URL = URL(fileURLWithPath: "/usr/bin/ditto")) {
        self.preferences = preferences
        self.cameraBase = cameraBase
        self.temporaryDirectory = temporaryDirectory
        self.archiveExecutable = archiveExecutable
        super.init()
    }

    func start(_ request: DownloadRequest) { startDownload(id: request.id, files: request.files) }

    func startDownload(id: String, files: [String]) {
        precondition(Thread.isMainThread)
        guard activeRequestID == nil, canStart(), !id.isEmpty, !files.isEmpty else { return }
        activeRequestID = id
        let cancellation = Progress(totalUnitCount: 1)
        self.cancellation = cancellation
        let format = preferences.format
        queue.addOperation {
            let job = DownloadOperation(id: id, files: files,
                directory: self.temporaryDirectory.appendingPathComponent("GRBrowser-\(UUID().uuidString)"),
                format: format, cancellation: cancellation)
            self.operation = job
            self.emit(job, phase: .preparing)
            DispatchQueue.main.async { self.resolveDestination(job) }
        }
    }

    func cancelDownload(id: String) {
        precondition(Thread.isMainThread)
        guard activeRequestID == id else { return }
        // Signal synchronous archive/copy work immediately; queue cleanup with delegate callbacks.
        cancellation?.cancel()
        queue.addOperation {
            guard let job = self.operation, job.id == id else { return }
            self.finish(job, phase: .cancelled, message: "Cancelled")
        }
    }

    private func checkCancellation() throws {
        if operation?.cancellation.isCancelled == true { throw URLError(.cancelled) }
    }

    private func downloadNext(_ job: DownloadOperation) {
        guard !job.cancellation.isCancelled else {
            finish(job, phase: .cancelled, message: "Cancelled"); return
        }
        let file = job.files[job.completed]
        let api = CameraAPI(base: cameraBase)
        guard let url = try? api.photo(file) else {
            finish(job, phase: .failed, message: "Invalid camera file path"); return
        }
        let request = api.request(url)
        currentTask = session?.downloadTask(with: request)
        job.stagedFile = nil
        job.lastProgressTime = .distantPast
        emit(job, phase: .downloading)
        currentTask?.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard downloadTask === currentTask, let job = operation else { return }
        let now = Date()
        guard now.timeIntervalSince(job.lastProgressTime) >= 0.1 else { return }
        job.lastProgressTime = now
        let fraction: Double? = totalBytesExpectedToWrite > 0
            ? min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) : nil
        let overall = fraction.map { (Double(job.completed) + $0) / Double(job.files.count) }
        emit(job, phase: .downloading, fraction: overall)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard downloadTask === currentTask, let job = operation else { return }
        do {
            try checkCancellation()
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
                throw failure("Camera returned HTTP \(status)")
            }
            let destination = job.photosDirectory.appendingPathComponent(job.files[job.completed])
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            // URLSession removes its temporary file when this delegate callback returns.
            try FileManager.default.moveItem(at: location, to: destination)
            job.stagedFile = destination
        } catch {
            finish(job, phase: .failed, message: "Download failed (\(job.filename)): \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === currentTask, let job = operation else { return }
        if let error = error {
            finish(job, phase: .failed, message: "Download failed (\(job.filename)): \(error.localizedDescription)")
            return
        }
        guard let stagedFile = job.stagedFile else {
            finish(job, phase: .failed, message: "Download failed: no file received")
            return
        }
        let filename = job.filename
        job.stagedFiles.append(stagedFile)
        job.completed += 1
        emit(job, phase: .downloading, fraction: Double(job.completed) / Double(job.files.count),
             filename: filename)
        currentTask = nil
        if job.completed < job.files.count {
            downloadNext(job)
        } else {
            prepareSave(job)
        }
    }

    private func prepareSave(_ job: DownloadOperation) {
        var saved = 0
        do {
            try checkCancellation()
            guard let directory = job.destination else { throw failure("No download folder selected") }
            let sources: [URL]
            if job.files.count > 1 && job.format == .zip {
                emit(job, phase: .archiving)
                let archive = job.directory.appendingPathComponent("GRIIIx_\(dateStr()).zip")
                do { try createArchive(photos: job.photosDirectory, destination: archive) }
                catch { throw failure("ZIP failed: \(error.localizedDescription)") }
                sources = [archive]
            } else { sources = job.stagedFiles }
            emit(job, phase: .saving)
            var lastName = ""
            for source in sources {
                try checkCancellation()
                let output = try publishFile(source, in: directory)
                lastName = output.lastPathComponent
                saved += 1
            }
            let description = sources.count == 1 ? lastName : "\(saved) photos"
            finish(job, phase: .completed, message: "Saved: \(description)")
        } catch {
            let total = job.format == .zip && job.files.count > 1 ? 1 : job.files.count
            finish(job, phase: .failed, message: "Save failed (\(saved)/\(total) saved): \(error.localizedDescription)")
        }
    }

    // Copy beside the destination, then atomically rename with exclusive creation.
    // RENAME_EXCL protects both existing files and races with other writers.
    func publishFile(_ source: URL, in directory: URL) throws -> URL {
        try checkCancellation()
        var template = Array(directory.appendingPathComponent(".GRBrowser-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = URL(fileURLWithPath: String(cString: template))
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try checkCancellation()
            try output.write(contentsOf: chunk)
        }
        try output.close()
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var suffix = 0
        while true {
            try checkCancellation()
            let name = suffix == 0 ? source.lastPathComponent
                : "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
            let destination = directory.appendingPathComponent(name)
            let result = temporary.path.withCString { from in
                destination.path.withCString { to in renamex_np(from, to, UInt32(RENAME_EXCL)) }
            }
            if result == 0 { return destination }
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            suffix += 1
        }
    }

    private func resolveDestination(_ job: DownloadOperation) {
        guard activeRequestID == job.id, !job.cancellation.isCancelled else { return }
        func begin(_ directory: URL) {
            self.queue.addOperation {
                guard self.operation === job, !job.cancellation.isCancelled else { return }
                job.destination = directory
                do {
                    for file in job.files { _ = try CameraAPI.components(file) }
                    try FileManager.default.createDirectory(at: job.photosDirectory, withIntermediateDirectories: true)
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.timeoutIntervalForRequest = 30
                    configuration.timeoutIntervalForResource = 600
                    self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.queue)
                    self.downloadNext(job)
                } catch {
                    self.finish(job, phase: .failed, message: "Download failed: \(error.localizedDescription)")
                }
            }
        }
        if let directory = preferences.folder(), AppPreferences.usableFolder(directory) {
            begin(directory)
        } else {
            chooseDirectory { directory in
                guard self.activeRequestID == job.id, !job.cancellation.isCancelled else { return }
                guard let directory = directory else {
                    self.queue.addOperation { self.finish(job, phase: .cancelled, message: "Cancelled") }
                    return
                }
                do { try self.preferences.setFolder(directory); begin(directory) }
                catch {
                    self.queue.addOperation {
                        self.finish(job, phase: .failed, message: "Folder unavailable: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func chooseDirectory(completion: @escaping (URL?) -> Void) {
        folderChooser(completion)
    }

    // These boundary methods also allow tests to inject save and filesystem failures.
    func createArchive(photos: URL, destination: URL) throws {
        try checkCancellation()
        let process = Process()
        process.executableURL = archiveExecutable
        process.arguments = ["-c", "-k", "--keepParent", photos.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        try process.run()
        while terminated.wait(timeout: .now() + 0.1) == .timedOut {
            if operation?.cancellation.isCancelled == true {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                throw URLError(.cancelled)
            }
        }
        process.waitUntilExit()
        try checkCancellation()
        guard process.terminationStatus == 0,
              let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber,
              size.int64Value > 0 else { throw failure("Could not create the photo archive") }
        let archive = try FileHandle(forReadingFrom: destination)
        defer { try? archive.close() }
        guard try archive.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]) else {
            throw failure("Invalid photo archive")
        }
    }

    private func emit(_ job: DownloadOperation, phase: DownloadPhase, fraction: Double? = nil,
                      filename: String? = nil, message: String? = nil) {
        let event = DownloadEvent(id: job.id, phase: phase, completed: job.completed,
            total: job.files.count, filename: filename ?? job.filename, fraction: fraction, message: message)
        DispatchQueue.main.async {
            guard self.activeRequestID == job.id else { return }
            if phase.terminal { self.activeRequestID = nil; self.cancellation = nil }
            self.lastEvent = event
            self.deliverEvent(event)
        }
    }

    func deliverEvent(_ event: DownloadEvent) { onEvent?(event) }

    private func finish(_ job: DownloadOperation, phase: DownloadPhase, message: String) {
        guard operation === job else { return }
        let cancelled = job.cancellation.isCancelled
        session?.invalidateAndCancel()
        session = nil
        currentTask = nil
        try? FileManager.default.removeItem(at: job.directory)
        operation = nil
        emit(job, phase: cancelled ? .cancelled : phase, message: cancelled ? "Cancelled" : message)
    }

    private func failure(_ message: String) -> Error {
        NSError(domain: "GRBrowser.Download", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private func dateStr() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}
