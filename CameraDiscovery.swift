import Foundation

// Passive observation only. The coordinator supplies admission; this type never joins or wakes.
final class CameraDiscovery {
    let wifi: WiFiAccess
    let authorization: WiFiAuthorization
    let bluetooth: CameraBluetoothAccess
    let worker: DispatchQueue
    let now: () -> Date
    var onChange: ((String?) -> Void)?
    var canApply: () -> Bool = { true }
    var canScan: () -> Bool = { true }
    var generation = 0
    var scanning = false
    var checkingCurrent = false
    var nextScan = Date.distantPast
    var nextBluetooth = Date.distantPast
    var nearby: [CameraNetwork] = []
    var current: CameraNetwork?
    var ready: Bool?

    init(wifi: WiFiAccess, authorization: WiFiAuthorization, bluetooth: CameraBluetoothAccess,
         worker: DispatchQueue, now: @escaping () -> Date) {
        self.wifi = wifi; self.authorization = authorization; self.bluetooth = bluetooth
        self.worker = worker; self.now = now
    }
    @discardableResult func setCurrent(_ network: CameraNetwork?, ready: Bool) -> Bool {
        let changed = current != network || self.ready != ready
        current = network; self.ready = ready
        return changed
    }
    func refreshCurrent() {
        guard !checkingCurrent, canApply() else { return }
        checkingCurrent = true
        let token = generation
        let allowed = authorization.allowed
        worker.async {
            let network = allowed ? self.wifi.current() : nil
            let ready = self.wifi.ready(on: nil)
            DispatchQueue.main.async {
                self.checkingCurrent = false
                guard self.generation == token, self.canApply() else { return }
                var changed = self.setCurrent(network, ready: ready)
                if !allowed, !self.nearby.isEmpty { self.nearby = []; changed = true }
                if changed { self.onChange?(nil) }
            }
        }
    }
    func refresh(requestAuthorization: Bool = false) {
        if requestAuthorization {
            authorization.request { [weak self] _ in self?.refresh() }; return
        }
        guard authorization.allowed else {
            nearby = []; current = nil
            refreshCurrent()
            onChange?("Allow GRBrowser in System Settings → Privacy & Security → Location Services to discover Wi-Fi names. Current Wi-Fi connection still works.")
            return
        }
        guard !scanning, canApply(), canScan() else { return }
        nextScan = now().addingTimeInterval(10)
        scanning = true; generation += 1
        let token = generation
        worker.async {
            let result = Result { try self.wifi.scan() }
            let current = self.wifi.current()
            let ready = self.wifi.ready(on: nil)
            DispatchQueue.main.async {
                self.scanning = false
                guard self.generation == token, self.canApply() else { return }
                self.setCurrent(current, ready: ready)
                switch result {
                case .success(let networks): self.nearby = networks; self.onChange?("")
                case .failure:
                    self.nearby = []
                    self.onChange?("Wi-Fi discovery unavailable. Use Current Wi-Fi or refresh discovery.")
                }
            }
        }
    }
    func pollBluetooth(discover: Bool, allowed: Bool, hasRemembered: Bool) {
        guard discover, allowed else { bluetooth.stopDiscovery(); return }
        let first = nextBluetooth == .distantPast
        guard now() >= nextBluetooth, first || hasRemembered else { return }
        nextBluetooth = now().addingTimeInterval(30)
        bluetooth.discover(explicit: false); onChange?(nil)
    }
    func findBluetooth(allowed: Bool) {
        guard allowed else { return }
        nextBluetooth = now().addingTimeInterval(30)
        bluetooth.discover(explicit: true); onChange?(nil)
    }
}
