import Foundation

// Reports observations only; session invalidation/history changes belong to CameraConnection.
final class SessionHealthMonitor {
    struct Observation {
        let initial: CameraNetwork?
        let final: CameraNetwork?
        let learnedIdentity: Bool
    }
    private let wifi: WiFiAccess
    private let camera: CameraVerification
    private let worker: DispatchQueue
    private var token: UUID?
    var isChecking: Bool { token != nil }

    init(wifi: WiFiAccess, camera: CameraVerification, worker: DispatchQueue) {
        self.wifi = wifi; self.camera = camera; self.worker = worker
    }
    func cancel() { token = nil; camera.cancel() }
    func check(expected: CameraNetwork?, allowed: Bool,
               observed: @escaping (CameraNetwork?, Bool) -> Void,
               completion: @escaping (Result<Observation, Error>) -> Void) {
        guard token == nil else { return }
        let generation = UUID(); token = generation
        func finish(_ result: Result<Observation, Error>) {
            guard self.token == generation else { return }
            self.token = nil; completion(result)
        }
        worker.async {
            let ready = self.wifi.ready(on: nil)
            let network = allowed ? self.wifi.current() : nil
            DispatchQueue.main.async {
                guard self.token == generation else { return }
                observed(network, ready)
                guard ready, expected == nil || network == nil || expected?.id == network?.id else {
                    finish(.failure(appError("Camera network changed."))); return
                }
                let needsIdentity = expected == nil && network != nil
                let respond: (Result<Void, Error>) -> Void = { result in
                    guard self.token == generation else { return }
                    guard case .success = result else { finish(result.map { _ in Observation(initial: nil, final: nil, learnedIdentity: false) }); return }
                    self.worker.async {
                        let final = allowed ? self.wifi.current() : nil
                        DispatchQueue.main.async {
                            guard self.token == generation else { return }
                            if let network = network, let final = final, network.id != final.id {
                                finish(.failure(appError("Camera network changed."))); return
                            }
                            finish(.success(Observation(initial: network, final: final, learnedIdentity: needsIdentity)))
                        }
                    }
                }
                if needsIdentity { self.camera.verify { respond($0.map { _ in () }) } }
                else { self.camera.ping(respond) }
            }
        }
    }
}
