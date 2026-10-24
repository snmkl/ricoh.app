import Foundation

struct CameraPhoto: Hashable, Identifiable {
    let dir: String
    let file: String
    var id: Self { self }
    var path: String { [dir, file].filter { !$0.isEmpty }.joined(separator: "/") }
}
protocol CameraVerification {
    func identify(_ identity: BluetoothIdentity, completion: @escaping (Result<Void, Error>) -> Void)
    func verify(_ completion: @escaping (Result<[CameraPhoto], Error>) -> Void)
    func ping(_ completion: @escaping (Result<Void, Error>) -> Void)
    func cancel()
}

extension CameraVerification {
    func identify(_ identity: BluetoothIdentity, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(appError("Camera identity verification is unavailable.")))
    }
    func ping(_ completion: @escaping (Result<Void, Error>) -> Void) {
        verify { completion($0.map { _ in () }) }
    }
}

final class HTTPCameraVerification: CameraVerification {
    private let base: URL
    private let session: URLSession
    private var generation = UUID()
    private var task: URLSessionDataTask?
    init(base: URL = URL(string: CAMERA_BASE)!) {
        self.base = base
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        session = URLSession(configuration: config)
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil }
    func ping(_ completion: @escaping (Result<Void, Error>) -> Void) {
        cancel()
        request("v1/ping", token: generation) { completion($0.map { _ in () }) }
    }
    func verify(_ completion: @escaping (Result<[CameraPhoto], Error>) -> Void) {
        cancel()
        let token = generation
        request("v1/ping", token: token) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                self.request("v1/photos", token: token) { result in
                    completion(result.flatMap { data in
                        Result {
                            do { return try Self.photos(from: data) }
                            catch { throw appError("Camera returned an invalid photo list.") }
                        }
                    })
                }
            }
        }
    }
    private func request(_ path: String, token: UUID, completion: @escaping (Result<Data, Error>) -> Void) {
        let api = CameraAPI(base: base)
        let request = api.request(try! api.url(path.split(separator: "/").map(String.init)))
        task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                guard error == nil, let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode), let data = data else {
                    completion(.failure(appError(path == "v1/ping" ? "Camera is unavailable." : "Could not load camera photos.")))
                    return
                }
                completion(.success(data))
            }
        }
        task?.resume()
    }
    func identify(_ identity: BluetoothIdentity, completion: @escaping (Result<Void, Error>) -> Void) {
        let token = generation
        request("v1/props", token: token) { result in
            completion(result.flatMap { data in Result {
                guard let props = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      props["model"] as? String == identity.model else {
                    throw appError("Wi-Fi camera identity does not match the selected Bluetooth camera.")
                }
                if let serial = identity.serial, let other = (props["serialNo"] ?? props["serialNumber"] ?? props["serial"]) as? String, serial != other {
                    throw appError("Wi-Fi camera serial does not match the selected Bluetooth camera.")
                }
            } })
        }
    }
    static func photos(from data: Data) throws -> [CameraPhoto] {
        let json = try JSONSerialization.jsonObject(with: data)
        var photos: [CameraPhoto] = []
        func append(_ value: Any, directory: String) throws {
            let filename = value as? String ?? (value as? [String: Any])?["name"] as? String
            guard let filename = filename, !filename.isEmpty else { throw appError("Invalid camera photo list.") }
            photos.append(CameraPhoto(dir: directory, file: filename))
        }
        if let dictionary = json as? [String: Any], let dirs = dictionary["dirs"] as? [[String: Any]] {
            for dir in dirs {
                guard let name = dir["name"] as? String, let files = dir["files"] as? [Any] else {
                    throw appError("Invalid camera photo list.")
                }
                for file in files { try append(file, directory: name) }
            }
        } else if let list = json as? [[String: Any]] {
            for item in list {
                guard let name = item["name"] as? String ?? item["file"] as? String else {
                    throw appError("Invalid camera photo list.")
                }
                try append(name, directory: item["dir"] as? String ?? item["directory"] as? String ?? "")
            }
        } else { throw appError("Invalid camera photo list.") }
        return photos.sorted { $0.file > $1.file }
    }
}
