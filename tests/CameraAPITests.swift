import Foundation

func runCameraAPITests() {
    let api = CameraAPI(base: fixtureURL)
    let path = "DCIM/a ' &?#%<name>.JPG"
    let url = try! api.photo(path, rendition: "thumb")
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    check(components.path == "/v1/photos/" + path && components.queryItems == [URLQueryItem(name: "size", value: "thumb")],
          "Encoded paths preserve punctuation without inventing query items")
    check(api.request(url).value(forHTTPHeaderField: "User-Agent") == CameraAPI.userAgent, "Shared User-Agent")
    for (index, path) in ["/absolute.JPG", "DCIM//empty.JPG", "../escape.JPG", "DCIM/./x.JPG", ""].enumerated() {
        check((try? api.photo(path)) == nil, "Invalid relative path rejected: \(path)")
        let failed = runDownload("invalid-path-\(index)", files: [path], expected: "failed")
        check(failed.saved.isEmpty && !failed.events.contains { $0.phase == .downloading }, "Invalid path fails before transfer or publication")
    }
    print("PASS: centralized camera URLs, punctuation, User-Agent and invalid path rejection before transfer")
}
