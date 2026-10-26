import Cocoa
import ImageIO

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

// Four distinct corners catch wrong rotation direction and mirrored EXIF values.
func fixtureOrientedJPEG(_ orientation: Int?) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 240, bitsPerPixel: 24)!
    let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
    for y in 0..<40 {
        for x in 0..<80 {
            let color = colors[(y / 20) * 2 + x / 40]
            for channel in 0..<3 { bitmap.bitmapData![y * 240 + x * 3 + channel] = color[channel] }
        }
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
    var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
    if let orientation = orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, bitmap.cgImage!, properties as CFDictionary)
    check(CGImageDestinationFinalize(destination), "Encode EXIF orientation fixture")
    return data as Data
}

@MainActor func runImageOrientationTests() {
    // Expected top-left, top-right, bottom-left, bottom-right colors for EXIF 1...8.
    let corners = ["RGBY", "GRYB", "YBGR", "BYRG", "RBGY", "BRYG", "YGBR", "GYRB"]
    let colors: [(Character, [CGFloat])] = [("R", [1, 0, 0]), ("G", [0, 1, 0]),
                                           ("B", [0, 0, 1]), ("Y", [1, 1, 0])]
    for orientation in [nil] + (1...8).map({ Optional($0) }) {
        let data = fixtureOrientedJPEG(orientation)
        let expected = corners[(orientation ?? 1) - 1]
        for rendition in [ImageRendition.thumbnail, .preview] {
            let transport = FakeImageTransport()
            let loader = CameraImageLoader(transport: transport, configuration: .init(thumbnailPixels: 16))
            let photo = CameraPhoto(dir: "DCIM", file: "orientation-\(orientation ?? 0).JPG")
            var result: Result<NSImage, Error>?
            _ = loader.request(photo, rendition: rendition) { result = $0 }
            transport.finish(0, .success(data))
            if orientation == nil {
                waitFor("missing EXIF requests camera metadata") { transport.requests.count == 2 }
                transport.finish(1, .success(Data("{}".utf8)))
            }
            waitFor("oriented \(rendition) decodes") { result != nil }
            let image = try! result!.get()
            let rotated = (orientation ?? 1) >= 5
            let longSide = rendition == .thumbnail ? 16 : 80
            let shortSide = longSide / 2
            let size = NSSize(width: rotated ? shortSide : longSide, height: rotated ? longSide : shortSide)
            check(image.size == size, "\(rendition) EXIF \(orientation ?? 0) has oriented dimensions")
            let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            var actual = ""
            for (x, y) in [(1, 1), (3, 1), (1, 3), (3, 3)] {
                let color = bitmap.colorAt(x: bitmap.pixelsWide * x / 4, y: bitmap.pixelsHigh * y / 4)!
                    .usingColorSpace(.deviceRGB)!
                let components = [color.redComponent, color.greenComponent, color.blueComponent]
                let nearest = colors.min { lhs, rhs in
                    zip(components, lhs.1).reduce(CGFloat(0)) { $0 + abs($1.0 - $1.1) } <
                    zip(components, rhs.1).reduce(CGFloat(0)) { $0 + abs($1.0 - $1.1) }
                }!
                actual.append(nearest.0)
            }
            check(actual == expected, "\(rendition) EXIF \(orientation ?? 0) corners: expected \(expected), got \(actual)")
            var cached: NSImage?
            _ = loader.request(photo, rendition: rendition) { cached = try? $0.get() }
            check(cached === image && transport.requests.count == (orientation == nil ? 2 : 1), "Oriented image reused from cache")
        }
    }
    // Reduced camera JPEGs can omit EXIF; /info supplies the source orientation.
    for orientation in 1...8 {
        for rendition in [ImageRendition.thumbnail, .preview] {
            let transport = FakeImageTransport()
            let loader = CameraImageLoader(transport: transport, configuration: .init(thumbnailPixels: 16))
            let photo = CameraPhoto(dir: "100 RICOH", file: "fallback #\(orientation).JPG")
            var result: Result<NSImage, Error>?
            _ = loader.request(photo, rendition: rendition) { result = $0 }
            transport.finish(0, .success(fixtureOrientedJPEG(nil)))
            waitFor("camera orientation request") { transport.requests.count == 2 }
            check(transport.requests[1].url.path == "/v1/photos/\(photo.path)/info" && transport.requests[1].url.query == nil,
                  "Metadata endpoint preserves path and has no size query")
            transport.finish(1, .success(Data("{\"orientation\":\(orientation)}".utf8)))
            waitFor("camera-oriented rendition") { result != nil }
            let image = try! result!.get()
            let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            let longSide = rendition == .thumbnail ? 16 : 80
            check(image.size == NSSize(width: orientation >= 5 ? longSide / 2 : longSide,
                                      height: orientation >= 5 ? longSide : longSide / 2), "Camera orientation dimensions")
            var actual = ""
            for (x, y) in [(1, 1), (3, 1), (1, 3), (3, 3)] {
                let color = bitmap.colorAt(x: bitmap.pixelsWide * x / 4, y: bitmap.pixelsHigh * y / 4)!.usingColorSpace(.deviceRGB)!
                let components = [color.redComponent, color.greenComponent, color.blueComponent]
                actual.append(colors.min { lhs, rhs in
                    zip(components, lhs.1).reduce(CGFloat(0)) { $0 + abs($1.0 - $1.1) } <
                    zip(components, rhs.1).reduce(CGFloat(0)) { $0 + abs($1.0 - $1.1) }
                }!.0)
            }
            check(actual == corners[orientation - 1], "Camera \(rendition) orientation \(orientation) corners: \(actual)")
            var cached: NSImage?
            _ = loader.request(photo, rendition: rendition) { cached = try? $0.get() }
            check(cached === image && transport.requests.count == 2, "Camera-oriented image cached without more requests")
        }
    }
    print("PASS: thumbnails and previews honor all eight embedded and camera-provided orientations, missing metadata and cache reuse")
}
@MainActor func runCameraOrientationLifecycleTests() {
    let photo = CameraPhoto(dir: "DCIM", file: "no-exif.JPG")
    let jpeg = fixtureOrientedJPEG(nil)
    let invalidMetadata: [Result<Data, Error>] = ["{}", "invalid JSON", "{\"orientation\":0}",
        "{\"orientation\":9}", "{\"orientation\":true}", "{\"orientation\":6.5}",
        "{\"orientation\":\"6\"}"].map { .success(Data($0.utf8)) } + [.failure(URLError(.timedOut))]
    for metadata in invalidMetadata {
        let transport = FakeImageTransport()
        let loader = CameraImageLoader(transport: transport)
        var result: Result<NSImage, Error>?
        _ = loader.request(photo, rendition: .preview) { result = $0 }
        transport.finish(0, .success(jpeg))
        waitFor("optional metadata fetch") { transport.requests.count == 2 }
        transport.finish(1, metadata)
        waitFor("image survives invalid/unavailable metadata") { result != nil }
        check((try? result!.get().size) == NSSize(width: 80, height: 40), "Metadata failure preserves an unrotated valid image")
        check(loader.activeCount == 0 && transport.requests.count == 2, "Metadata failure releases slot without retry")
    }

    let transport = FakeImageTransport()
    let loader = CameraImageLoader(transport: transport, configuration: .init(concurrency: 1))
    var callbacks = 0
    let first = loader.request(photo, rendition: .thumbnail) { _ in callbacks += 1 }
    let second = loader.request(photo, rendition: .thumbnail) { _ in callbacks += 1 }
    var preview: NSImage?
    _ = loader.request(photo, rendition: .preview) { preview = try? $0.get() }
    transport.finish(0, .success(jpeg))
    waitFor("shared metadata demand") { transport.requests.count == 2 }
    check(loader.activeCount == 1 && transport.requests[1].url.lastPathComponent == "info", "Metadata shares image concurrency slot")
    first()
    check(!transport.requests[1].cancelled, "Shared image demand retains metadata")
    second()
    check(transport.requests[1].cancelled && transport.requests.count == 2, "Last consumer cancels metadata and awaits acknowledgement")
    transport.finish(1, .success(Data("{\"orientation\":6}".utf8)))
    waitFor("queued preview admitted after metadata cancellation") { transport.requests.count == 3 }
    transport.finish(2, .success(fixtureOrientedJPEG(8)))
    waitFor("preview after cancelled thumbnail") { preview != nil }
    check(callbacks == 0 && preview!.size == NSSize(width: 40, height: 80), "Cancelled metadata cannot deliver or double-rotate embedded EXIF")

    _ = loader.request(photo, rendition: .thumbnail) { _ in callbacks += 1 }
    transport.finish(3, .success(jpeg))
    waitFor("old library metadata fetch") { transport.requests.count == 5 }
    loader.invalidate()
    var reconnected: NSImage?
    _ = loader.request(photo, rendition: .thumbnail) { reconnected = try? $0.get() }
    check(transport.requests[4].cancelled && transport.requests.count == 5 && loader.cachedCost == 0,
          "Library invalidation cancels metadata and clears oriented cache")
    transport.finish(4, .success(Data("{\"orientation\":6}".utf8)))
    waitFor("new library admission") { transport.requests.count == 6 }
    transport.finish(5, .success(fixtureOrientedJPEG(1)))
    waitFor("new library image") { reconnected != nil }
    check(callbacks == 0 && reconnected!.size == NSSize(width: 80, height: 40), "Stale orientation never enters a new library")
    print("PASS: optional metadata failures, bounded/coalesced metadata, cancellation and generation isolation")
}
@MainActor func runImageLoaderTests() {
    runImageOrientationTests()
    runCameraOrientationLifecycleTests()
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
