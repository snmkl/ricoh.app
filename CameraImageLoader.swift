import Cocoa
import Combine
import CoreImage
import ImageIO

protocol CameraImageTransport {
    func fetch(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) -> () -> Void
}
final class HTTPImageTransport: CameraImageTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }
    func fetch(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) -> () -> Void {
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  let data = data else { completion(.failure(URLError(.badServerResponse))); return }
            completion(.success(data))
        }
        task.resume()
        return { task.cancel() }
    }
}

enum ImageRendition: Hashable, Sendable { case thumbnail, preview }
struct CameraImageKey: Hashable {
    let generation: UUID
    let photo: CameraPhoto
    let rendition: ImageRendition
}

@MainActor
final class CameraImageLoader: ObservableObject {
    struct Configuration {
        var concurrency = 2
        var cacheLimit = 64 * 1024 * 1024
        var thumbnailPixels = 320
    }
    private final class Work {
        let key: CameraImageKey
        let token = UUID()
        let order: Int
        var consumers: [UUID: (Result<NSImage, Error>) -> Void] = [:]
        var cancel: (() -> Void)?
        var retired = false
        init(key: CameraImageKey, order: Int) { self.key = key; self.order = order }
    }
    private struct Cached {
        let image: NSImage
        let cost: Int
        var access: Int
    }
    @Published private(set) var generation = UUID()
    private let configuration: Configuration
    private let transport: CameraImageTransport
    private let api: CameraAPI
    private let decodeQueue = DispatchQueue(label: "GRBrowser.images.decode", qos: .userInitiated)
    nonisolated private static let orientationContext = CIContext()
    private var work: [CameraImageKey: Work] = [:]
    // Retired requests keep their concurrency slot until cancellation is acknowledged.
    private var active: [UUID: Work] = [:]
    private var cache: [CameraImageKey: Cached] = [:]
    private var sequence = 0
    private(set) var cachedCost = 0
    var activeCount: Int { active.count }
    var cacheLimit: Int { configuration.cacheLimit }
    var concurrencyLimit: Int { configuration.concurrency }

    init(base: URL = URL(string: CAMERA_BASE)!, transport: CameraImageTransport = HTTPImageTransport(),
         configuration: Configuration = Configuration()) {
        precondition(configuration.concurrency > 0 && configuration.cacheLimit >= 0 && configuration.thumbnailPixels > 0)
        api = CameraAPI(base: base); self.transport = transport; self.configuration = configuration
    }
    // Demand is explicit, so tiles and preview can release it independently.
    @discardableResult func request(_ photo: CameraPhoto, rendition: ImageRendition,
                 completion: @escaping (Result<NSImage, Error>) -> Void) -> () -> Void {
        let key = CameraImageKey(generation: generation, photo: photo, rendition: rendition)
        sequence += 1
        if var entry = cache[key] {
            entry.access = sequence; cache[key] = entry
            completion(.success(entry.image)); return {}
        }
        let consumer = UUID()
        let job = work[key] ?? Work(key: key, order: sequence)
        job.consumers[consumer] = completion
        work[key] = job
        pump()
        return { [weak self, weak job] in
            guard let self = self, let job = job else { return }
            job.consumers.removeValue(forKey: consumer)
            if job.consumers.isEmpty { self.retire(job); self.pump() }
        }
    }
    func invalidate() {
        generation = UUID()
        for job in Array(work.values) { retire(job) }
        cache.removeAll(); cachedCost = 0
    }
    private func retire(_ job: Work) {
        guard !job.retired else { return }
        job.retired = true; job.consumers.removeAll()
        if work[job.key] === job { work.removeValue(forKey: job.key) }
        job.cancel?()
    }
    private func pump() {
        while active.count < configuration.concurrency {
            let pending = work.values.filter { $0.cancel == nil && !$0.retired }
            guard let job = pending.min(by: {
                if $0.key.rendition != $1.key.rendition { return $0.key.rendition == .preview }
                return $0.order < $1.order
            }) else { return }
            let url: URL
            do { url = try api.photo(job.key.photo.path, rendition: job.key.rendition == .thumbnail ? "thumb" : "view") }
            catch {
                work.removeValue(forKey: job.key)
                let consumers = Array(job.consumers.values); job.consumers.removeAll()
                consumers.forEach { $0(.failure(error)) }; continue
            }
            active[job.token] = job
            job.cancel = transport.fetch(api.request(url)) { [weak self, weak job] result in
                DispatchQueue.main.async {
                    guard let self = self, let job = job else { return }
                    self.complete(job, result: result)
                }
            }
        }
    }
    private func accepts(_ job: Work) -> Bool {
        guard active[job.token] != nil else { return false }
        guard !job.retired, job.key.generation == generation, work[job.key] === job else {
            active.removeValue(forKey: job.token); pump(); return false
        }
        return true
    }
    private func complete(_ job: Work, result: Result<Data, Error>) {
        guard accepts(job) else { return }
        guard case .success(let data) = result else { decode(job, result: result); return }
        let token = job.token
        decodeQueue.async {
            let needsOrientation = Self.needsCameraOrientation(data)
            DispatchQueue.main.async {
                guard let job = self.active[token], self.accepts(job) else { return }
                if needsOrientation { self.fetchOrientation(job, data: data) }
                else { self.decode(job, result: result) }
            }
        }
    }
    nonisolated private static func needsCameraOrientation(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.jpeg" else { return false }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let orientation = properties?[kCGImagePropertyOrientation] as? Int else { return true }
        return !(1...8).contains(orientation)
    }
    private func fetchOrientation(_ job: Work, data: Data) {
        // Reduced camera JPEGs may omit EXIF. Keep the same scheduler slot and
        // cancellation token through /info so metadata obeys the image limit too.
        guard let url = try? api.photoInfo(job.key.photo.path) else { decode(job, result: .success(data)); return }
        job.cancel = transport.fetch(api.request(url)) { [weak self, weak job] result in
            DispatchQueue.main.async {
                guard let self = self, let job = job, self.accepts(job) else { return }
                struct Metadata: Decodable { let orientation: Int }
                let orientation = try? result.flatMap { data in
                    Result { try JSONDecoder().decode(Metadata.self, from: data).orientation }
                }.get()
                // Missing or failed metadata must not hide an otherwise valid image.
                self.decode(job, result: .success(data), orientation: orientation.flatMap { (1...8).contains($0) ? $0 : nil })
            }
        }
    }
    private func decode(_ job: Work, result: Result<Data, Error>, orientation: Int? = nil) {
        let pixels = configuration.thumbnailPixels
        let rendition = job.key.rendition
        let token = job.token
        decodeQueue.async {
            let decoded = result.flatMap { Self.decode($0, rendition: rendition, pixels: pixels, orientation: orientation) }
            DispatchQueue.main.async {
                guard let job = self.active[token] else { return }
                self.finishDecoded(job, result: decoded)
            }
        }
    }
    nonisolated private static func decode(_ data: Data, rendition: ImageRendition, pixels: Int,
                                          orientation: Int?) -> Result<(NSImage, Int), Error> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return .failure(URLError(.cannotDecodeContentData)) }
        let maxPixels: Int
        if rendition == .thumbnail {
            maxPixels = pixels
        } else {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0 else { return .failure(URLError(.cannotDecodeContentData)) }
            maxPixels = max(width, height)
        }
        // CGImage alone loses EXIF orientation. Apply it to pixels for both renditions;
        // the preview uses the source dimensions to retain its full resolution.
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            return .failure(URLError(.cannotDecodeContentData))
        }
        if let orientation = orientation, orientation != 1 {
            let oriented = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation))
            guard let transformed = orientationContext.createCGImage(oriented, from: oriented.extent) else {
                return .failure(URLError(.cannotDecodeContentData))
            }
            image = transformed
        }
        return .success((NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), image.bytesPerRow * image.height))
    }
    private func finishDecoded(_ job: Work, result: Result<(NSImage, Int), Error>) {
        guard active.removeValue(forKey: job.token) != nil else { return }
        defer { pump() }
        guard !job.retired, job.key.generation == generation, work[job.key] === job else { return }
        work.removeValue(forKey: job.key)
        if case .success(let (image, cost)) = result, cost <= configuration.cacheLimit {
            sequence += 1
            while cachedCost + cost > configuration.cacheLimit, let oldest = cache.min(by: { $0.value.access < $1.value.access }) {
                cachedCost -= oldest.value.cost; cache.removeValue(forKey: oldest.key)
            }
            cache[job.key] = Cached(image: image, cost: cost, access: sequence); cachedCost += cost
        }
        let consumers = Array(job.consumers.values); job.consumers.removeAll()
        consumers.forEach { $0(result.map { $0.0 }) }
    }
}
