import Foundation
import CoreBluetooth

// The manager is deliberately lazy: constructing a Wi-Fi-only app/test never requests Bluetooth access.
final class CoreBluetoothTransport: NSObject, BluetoothTransport, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var manager: CBCentralManager?
    private var peers: [UUID: CBPeripheral] = [:]
    private var observed: [UUID: BluetoothObservation] = [:]
    private var peripheral: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private var waitingServices = Set<CBUUID>()
    private var connectCompletion: ((Result<Void, Error>) -> Void)?
    private var pendingRead: (CBCharacteristic, (Result<Data, Error>) -> Void)?
    private var pendingWrite: (CBCharacteristic, (Result<Void, Error>) -> Void)?
    private var operation = UUID()
    private var link = UUID()
    private var discovery = UUID()
    private var wantsDiscovery = false
    private var requestedID: UUID?
    private var draining = false
    private var drainCompletions: [() -> Void] = []
    private var didConnect = false
    var onChange: (() -> Void)?
    var connectedID: UUID? { didConnect && !draining ? peripheral?.identifier : nil }
    var observations: [BluetoothObservation] { Array(observed.values) }
    var state: String {
        switch CBManager.authorization {
        case .denied, .restricted: return "Bluetooth access denied. Enable GRBrowser in System Settings → Privacy & Security → Bluetooth."
        case .notDetermined: return "Bluetooth not enabled"
        default: break
        }
        guard let manager = manager else { return "Bluetooth available" }
        switch manager.state {
        case .poweredOn: return "Bluetooth on"
        case .poweredOff: return "Bluetooth is off. Turn it on in System Settings."
        case .unauthorized: return "Bluetooth access denied. Enable it in System Settings."
        case .unsupported: return "Bluetooth is unavailable on this Mac."
        default: return "Waiting for Bluetooth…"
        }
    }
    private func initialize(explicit: Bool) {
        guard manager == nil, explicit || CBManager.authorization == .allowedAlways else { return }
        manager = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    func discover(explicit: Bool) {
        initialize(explicit: explicit)
        guard let manager = manager, peripheral == nil, !draining else { return }
        wantsDiscovery = true
        if manager.state == .poweredOn { scan() }
        onChange?()
    }
    private func systemPeers() {
        guard let manager = manager, manager.state == .poweredOn else { return }
        // Refresh system-connected assertions instead of treating them as permanent observations.
        observed = observed.mapValues { BluetoothObservation(id: $0.id, name: $0.name, seen: $0.seen, systemConnected: false) }
        for peer in manager.retrieveConnectedPeripherals(withServices: RicohBLE.services.map(CBUUID.init(string:))) {
            peers[peer.identifier] = peer
            observed[peer.identifier] = BluetoothObservation(id: peer.identifier, name: peer.name ?? "Ricoh camera",
                                                             seen: Date(), systemConnected: true)
        }
    }
    private func scan() {
        guard let manager = manager, manager.state == .poweredOn, peripheral == nil, !draining else { return }
        manager.stopScan(); systemPeers()
        let token = UUID(); discovery = token
        manager.scanForPeripherals(withServices: [CBUUID(string: "84A0DD62-E8AA-4D0F-91DB-819B6724C69E")])
        // Some GR advertisements omit the service filter; a bounded name scan is only a candidate search.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.discovery == token, self.peripheral == nil, self.wantsDiscovery else { return }
            self.manager?.stopScan(); self.manager?.scanForPeripherals(withServices: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.discovery == token else { return }
            self.stopDiscovery(); self.onChange?()
        }
        onChange?()
    }
    func stopDiscovery() { discovery = UUID(); wantsDiscovery = false; if requestedID == nil { manager?.stopScan() } }
    func connect(_ id: UUID, completion: @escaping (Result<Void, Error>) -> Void) {
        guard peripheral == nil, !draining else { completion(.failure(BluetoothFailure.unavailable("Bluetooth is still disconnecting."))); return }
        stopDiscovery(); initialize(explicit: true)
        requestedID = id; connectCompletion = completion; link = UUID()
        let token = link
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.link == token, self.connectCompletion != nil else { return }
            self.fail(BluetoothFailure.timeout)
        }
        if manager?.state == .poweredOn { findTarget() }
        else if let manager = manager, manager.state == .poweredOff || manager.state == .unauthorized || manager.state == .unsupported {
            fail(BluetoothFailure.unavailable(state))
        }
        onChange?()
    }
    private func findTarget() {
        guard let manager = manager, let id = requestedID, peripheral == nil, !draining else { return }
        // A retained observation does not prove range. connect itself has a deadline.
        let peer = manager.retrievePeripherals(withIdentifiers: [id]).first ?? peers[id]
            ?? manager.retrieveConnectedPeripherals(withServices: RicohBLE.services.map(CBUUID.init(string:))).first { $0.identifier == id }
        if let peer = peer { attach(peer) }
        else { manager.scanForPeripherals(withServices: nil) }
    }
    private func attach(_ peer: CBPeripheral) {
        manager?.stopScan(); peripheral = peer; peer.delegate = self; didConnect = false
        characteristics = [:]; manager?.connect(peer)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if requestedID != nil { findTarget() }
            else if wantsDiscovery { scan() }
        } else if central.state != .unknown && central.state != .resetting {
            fail(BluetoothFailure.unavailable(state))
            retire()
        }
        onChange?()
    }
    func centralManager(_ central: CBCentralManager, didDiscover peer: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peer.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let candidate = name.uppercased().hasPrefix("GR_") || name.uppercased().hasPrefix("RICOH")
            || services.contains(CBUUID(string: "84A0DD62-E8AA-4D0F-91DB-819B6724C69E"))
        guard candidate || peer.identifier == requestedID else { return }
        peers[peer.identifier] = peer
        observed[peer.identifier] = BluetoothObservation(id: peer.identifier, name: name.isEmpty ? "Ricoh candidate" : name,
                                                         seen: Date(), systemConnected: false)
        if peer.identifier == requestedID, peripheral == nil, !draining { attach(peer) }
        onChange?()
    }
    func centralManager(_ central: CBCentralManager, didConnect peer: CBPeripheral) {
        guard peer === peripheral, !draining else { central.cancelPeripheralConnection(peer); return }
        didConnect = true; onChange?()
        peer.discoverServices(RicohBLE.discoveryServices.map(CBUUID.init(string:)))
        armTimeout(5)
    }
    func peripheral(_ peer: CBPeripheral, didDiscoverServices error: Error?) {
        guard peer === peripheral, !draining, connectCompletion != nil else { return }
        guard error == nil, let services = peer.services,
              RicohBLE.services.allSatisfy({ id in services.contains { $0.uuid == CBUUID(string: id) } }) else {
            fail(BluetoothFailure.unsupported); return
        }
        waitingServices = Set(services.map(\.uuid))
        for service in services {
            let ids = (RicohBLE.required[service.uuid.uuidString] ?? []) + (RicohBLE.optional[service.uuid.uuidString] ?? [])
            peer.discoverCharacteristics(ids.map(CBUUID.init(string:)), for: service)
        }
    }
    func peripheral(_ peer: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peer === peripheral, !draining, connectCompletion != nil else { return }
        if error != nil, RicohBLE.services.contains(service.uuid.uuidString) { fail(BluetoothFailure.unsupported); return }
        if error == nil {
            for characteristic in service.characteristics ?? [] { characteristics[characteristic.uuid.uuidString] = characteristic }
        }
        waitingServices.remove(service.uuid)
        guard waitingServices.isEmpty else { return }
        let readable = RicohBLE.required.values.flatMap { $0 }
        guard readable.allSatisfy({ characteristics[$0]?.properties.contains(.read) == true }),
              [RicohBLE.power, RicohBLE.network].allSatisfy({ characteristics[$0]?.properties.contains(.write) == true }) else {
            fail(BluetoothFailure.unsupported); return
        }
        operation = UUID(); requestedID = nil
        let done = connectCompletion; connectCompletion = nil; done?(.success(()))
    }
    private func mapped(_ error: Error) -> Error {
        let value = error as NSError
        if value.domain == CBATTErrorDomain {
            if value.code == 0x80 { return BluetoothFailure.rejected }
            if [5, 8, 12, 15].contains(value.code) { return BluetoothFailure.pairing }
        }
        // Never expose a framework's raw diagnostic payload/credentials in the UI.
        return BluetoothFailure.unavailable("Bluetooth camera operation failed. Check pairing and retry, or use camera Wi-Fi.")
    }
    func read(_ uuid: String, pairing: Bool, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let peer = peripheral, connectedID != nil else { completion(.failure(BluetoothFailure.disconnected)); return }
        if uuid == RicohBLE.serial, characteristics[uuid]?.properties.contains(.read) != true { completion(.success(Data())); return }
        guard pendingRead == nil, pendingWrite == nil, let characteristic = characteristics[uuid], characteristic.properties.contains(.read) else {
            completion(.failure(BluetoothFailure.unsupported)); return
        }
        pendingRead = (characteristic, completion); armTimeout(pairing ? 120 : 5); peer.readValue(for: characteristic)
    }
    func write(_ uuid: String, value: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let peer = peripheral, connectedID != nil else { completion(.failure(BluetoothFailure.disconnected)); return }
        let validControl = [RicohBLE.power, RicohBLE.network].contains(uuid) && value == Data([1])
        let validName = uuid == RicohBLE.pairedDeviceName && String(data: value, encoding: .utf8)
            .flatMap(RicohBLE.deviceNamePayload) == value && !value.isEmpty
        guard pendingRead == nil, pendingWrite == nil, validControl || validName,
              value.count <= peer.maximumWriteValueLength(for: .withResponse),
              let characteristic = characteristics[uuid], characteristic.properties.contains(.write) else {
            completion(.failure(BluetoothFailure.unsupported)); return
        }
        pendingWrite = (characteristic, completion); armTimeout(5); peer.writeValue(value, for: characteristic, type: .withResponse)
    }
    func peripheral(_ peer: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peer === peripheral, !draining, let pending = pendingRead, pending.0 === characteristic else { return }
        pendingRead = nil; operation = UUID()
        if let error = error { pending.1(.failure(mapped(error))) }
        else if let data = characteristic.value { pending.1(.success(data)) }
        else { pending.1(.failure(BluetoothFailure.invalidValue)) }
    }
    func peripheral(_ peer: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peer === peripheral, !draining, let pending = pendingWrite, pending.0 === characteristic else { return }
        pendingWrite = nil; operation = UUID()
        if let error = error { pending.1(.failure(mapped(error))) } else { pending.1(.success(())) }
    }
    func peripheral(_ peer: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peer === peripheral else { return }; fail(BluetoothFailure.unsupported)
    }
    private func armTimeout(_ seconds: TimeInterval) {
        let token = UUID(); operation = token
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self, self.operation == token else { return }
            self.fail(BluetoothFailure.timeout)
        }
    }
    private func fail(_ error: Error) {
        let connected = connectCompletion; let read = pendingRead?.1; let write = pendingWrite?.1
        connectCompletion = nil; pendingRead = nil; pendingWrite = nil; operation = UUID()
        // Retire the link before reporting failure; no new GATT request can consume an old callback.
        disconnect {}
        connected?(.failure(error)); read?(.failure(error)); write?(.failure(error))
    }
    func disconnect(_ completion: @escaping () -> Void) {
        drainCompletions.append(completion)
        stopDiscovery(); operation = UUID(); requestedID = nil; manager?.stopScan()
        connectCompletion = nil; pendingRead = nil; pendingWrite = nil
        if draining { return }
        draining = true
        if let peer = peripheral, peer.state != .disconnected { manager?.cancelPeripheralConnection(peer) }
        else { retire() }
        onChange?()
    }
    private func retire() {
        peripheral?.delegate = nil; peripheral = nil; didConnect = false
        characteristics = [:]; waitingServices = []; link = UUID(); draining = false
        let callbacks = drainCompletions; drainCompletions = []; callbacks.forEach { $0() }
        onChange?()
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peer: CBPeripheral, error: Error?) {
        guard peer === peripheral else { return }
        if draining { retire() } else { fail(BluetoothFailure.disconnected) }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peer: CBPeripheral, error: Error?) {
        guard peer === peripheral else { return }
        if draining { retire() }
        else {
            didConnect = false
            fail(BluetoothFailure.disconnected)
        }
    }
}
