import Cocoa

final class FakeImageTransport: CameraImageTransport {
    struct Request {
        let url: URL
        let complete: (Result<Data, Error>) -> Void
        var cancelled = false
    }
    var requests: [Request] = []
    func fetch(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) -> () -> Void {
        let index = requests.count
        requests.append(Request(url: request.url!, complete: completion))
        return { self.requests[index].cancelled = true }
    }
    func finish(_ index: Int, _ result: Result<Data, Error>) { requests[index].complete(result) }
}
func fixturePNG() -> Data {
    let context = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 320,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}
@MainActor func runImageLoaderTests() {
    let transport = FakeImageTransport()
    let loader = CameraImageLoader(transport: transport)
    check(loader.concurrencyLimit == 2 && loader.cacheLimit == 64 * 1024 * 1024, "Default image concurrency and decoded cache bounds")
    let photos = (0..<6).map { CameraPhoto(dir: "DCIM", file: "\($0).JPG") }
    let png = fixturePNG()
    var loaded = 0
    let first = loader.request(photos[0], rendition: .thumbnail) { if case .success = $0 { loaded += 1 } }
    let duplicate = loader.request(photos[0], rendition: .thumbnail) { if case .success = $0 { loaded += 1 } }
    _ = loader.request(photos[1], rendition: .thumbnail) { _ in }
    _ = loader.request(photos[2], rendition: .thumbnail) { _ in }
    _ = loader.request(photos[3], rendition: .preview) { _ in }
    check(transport.requests.count == 2 && loader.activeCount == 2, "Identical image demand coalesces within bound")
    first()
    check(!transport.requests[0].cancelled, "Shared demand keeps transfer alive")
    transport.finish(0, .success(png))
    waitFor("preview receives next image slot") { transport.requests.count == 3 }
    check(loaded == 1 && transport.requests[2].url.query == "size=view", "Preview has priority over queued thumbnails")
    duplicate()
    var cached = false
    _ = loader.request(photos[0], rendition: .thumbnail) { if case .success = $0 { cached = true } }
    check(cached && transport.requests.count == 3, "Loaded image reused without request")
    let abandoned = loader.request(photos[4], rendition: .thumbnail) { _ in check(false, "Cancelled queue callback") }
    abandoned()
    loader.invalidate()
    check(loader.cachedCost == 0 && transport.requests.dropFirst().allSatisfy(\.cancelled), "Invalidation clears cache and cancels in-flight demand")
    var reconnected = false
    _ = loader.request(photos[0], rendition: .thumbnail) { if case .success = $0 { reconnected = true } }
    check(transport.requests.count == 3, "Retired transfers hold slots until cancellation acknowledgement")
    transport.finish(1, .success(png)); transport.finish(2, .success(png))
    waitFor("new generation request starts") { transport.requests.count == 4 }
    check(!reconnected && loader.activeCount <= 2, "Old matching filenames cannot deliver into new library")
    transport.finish(3, .success(png)); waitFor("new generation image") { reconnected }

    let boundedTransport = FakeImageTransport()
    let bounded = CameraImageLoader(transport: boundedTransport,
        configuration: .init(concurrency: 1, cacheLimit: 1024, thumbnailPixels: 16))
    for index in 0..<3 {
        var image: NSImage?
        _ = bounded.request(photos[index], rendition: .thumbnail) { image = try? $0.get() }
        boundedTransport.finish(index, .success(png))
        waitFor("downsampled image") { image != nil }
        check(image!.size.width <= 16 && bounded.cachedCost <= 1024 && bounded.activeCount == 0,
              "Thumbnail downsampling and injected decoded cache limit")
    }
    _ = bounded.request(photos[0], rendition: .thumbnail) { _ in }
    check(boundedTransport.requests.count == 4, "Least recently used decoded image evicted")
    boundedTransport.finish(3, .failure(URLError(.timedOut)))
    waitFor("failed image releases admission") { bounded.activeCount == 0 }
    let failedCount = boundedTransport.requests.count
    let settle = Date().addingTimeInterval(0.1)
    waitFor("no automatic retry loop") { Date() >= settle }
    check(boundedTransport.requests.count == failedCount, "Failed thumbnails do not automatically retry")
    var malformed = false
    _ = bounded.request(photos[0], rendition: .thumbnail) { if case .failure = $0 { malformed = true } }
    boundedTransport.finish(4, .success(Data("invalid image".utf8)))
    waitFor("malformed image placeholder outcome") { malformed }
    var retry = false
    _ = bounded.request(photos[0], rendition: .thumbnail) { if case .success = $0 { retry = true } }
    boundedTransport.finish(5, .success(png)); waitFor("renewed demand retry") { retry }
    var cancelledCallback = false
    let cancel = bounded.request(CameraPhoto(dir: "OTHER", file: photos[0].file), rendition: .thumbnail) { _ in cancelledCallback = true }
    check(boundedTransport.requests.count == 7, "Duplicate basenames have distinct image identities")
    cancel(); check(boundedTransport.requests[6].cancelled, "Last demand cancels active image transfer")
    boundedTransport.finish(6, .success(png))
    waitFor("active cancellation acknowledged") { bounded.activeCount == 0 }
    check(!cancelledCallback, "Stopped image consumer never receives late data")
    print("PASS: bounded image scheduler/cache, coalescing, preview priority, cancellation, generation isolation, downsampling, failures and renewed-demand retries")
}
