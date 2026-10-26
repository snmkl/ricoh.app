import Foundation

let CAMERA_BASE = "http://192.168.0.1"

struct CameraAPI {
    static let userAgent = "GRBrowser/1.0"
    let base: URL

    static func components(_ relativePath: String) throws -> [String] {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0")
        }) else { throw appError("Invalid camera file path") }
        return parts
    }
    func url(_ path: [String], rendition: String? = nil) throws -> URL {
        guard path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\0") }),
              var value = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw appError("Invalid camera file path")
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let prefix = value.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = path.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        value.percentEncodedPath = "/" + [prefix, encoded].filter { !$0.isEmpty }.joined(separator: "/")
        value.queryItems = rendition.map { [URLQueryItem(name: "size", value: $0)] }
        guard let url = value.url else { throw appError("Invalid camera URL") }
        return url
    }
    func photo(_ path: String, rendition: String? = nil) throws -> URL {
        try url(["v1", "photos"] + Self.components(path), rendition: rendition)
    }
    func photoInfo(_ path: String) throws -> URL {
        try url(["v1", "photos"] + Self.components(path) + ["info"])
    }
    func request(_ url: URL, timeout: TimeInterval? = nil) -> URLRequest {
        var value = URLRequest(url: url)
        if let timeout = timeout { value.timeoutInterval = timeout }
        value.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return value
    }
}
