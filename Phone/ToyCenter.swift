import CoreBluetooth
import Foundation

/// Bluetooth: what is near in setup mode, and the link to the Bluetooth-only
/// toys this phone talks for (server docs, "Bluetooth-only toys").
///
/// One GATT service for every toy, two characteristics, the same typed JSON
/// as on the socket: `rx` phone → toy (write with response), `tx` toy →
/// phone (indicate). A message goes in chunks, each led by one flag byte:
/// 0x01 more follows, 0x00 the last. Both need an encrypted, bonded link, so
/// iOS asks to pair on the first touch.
///
/// The radio is switched on only when it is needed (the nearby search, or a
/// toy already connected): iOS asks about Bluetooth the moment it is.
@MainActor
final class ToyCenter: NSObject, ObservableObject {
    static let service = CBUUID(string: "80e80001-eb5b-4050-86c3-f6516f771280")
    static let rx = CBUUID(string: "80e80002-eb5b-4050-86c3-f6516f771280")
    static let tx = CBUUID(string: "80e80003-eb5b-4050-86c3-f6516f771280")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    /// A message is at most 4 KB.
    static let maxMessage = 4096
    /// Only what is very near shows in the search.
    static let nearEnough = -75

    enum Radio {
        case unknown, on, off, denied, unsupported
    }

    /// Something in setup mode nearby: a board with Wi-Fi (its name starts
    /// with `LoveAround-`) or a toy without (it advertises the service).
    struct Found: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int
        var toy: Bool
        var seen = Date()

        var veryNear: Bool { rssi >= -60 }
    }

    @Published private(set) var radio: Radio = .unknown
    @Published private(set) var found: [Found] = []
    /// The toys connected right now, by device id.
    @Published private(set) var near: Set<String> = []

    /// The toy told what it is made of (at every connect).
    var onAbout: (_ device: String, _ about: [String: Any]) -> Void = { _, _ in }
    /// The link is up and the toy listens: time to write its settings.
    var onNear: (_ device: String) -> Void = { _ in }
    var onApplied: (_ device: String, _ rev: String) -> Void = { _, _ in }
    var onBattery: (_ device: String, _ level: Int) -> Void = { _, _ in }
    var onPress: (_ device: String, _ part: String, _ gesture: String) -> Void = { _, _, _ in }

    /// `--demo`: no radio, a made-up board and a made-up toy.
    var demo = false

    private var central: CBCentralManager?
    private var scanning = false
    private var pruning: Timer?
    private var peers: [UUID: Peer] = [:]
    private let defaults: UserDefaults

    /// A toy's link: its characteristics, the message being put together,
    /// the chunks waiting to go.
    private final class Peer {
        let peripheral: CBPeripheral
        var device: String?
        var rx: CBCharacteristic?
        var ready = false
        var incoming = Data()
        var outbox: [Data] = []
        var writing = false
        var about: [String: Any]?
        var waiting: CheckedContinuation<[String: Any], Error>?

        init(_ peripheral: CBPeripheral) {
            self.peripheral = peripheral
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Which toys are this phone's

    /// Device id → the peripheral's id on this iPhone. A toy bonds with one
    /// phone, so the other phones of the account have no entry for it.
    private var known: [String: String] {
        get { defaults.dictionary(forKey: "toys") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "toys") }
    }

    func isMine(_ device: String) -> Bool {
        demo || known[device] != nil
    }

    /// At launch: with a toy of this phone's, the radio goes on and the
    /// link comes back by itself, in the background too.
    func start() {
        guard !demo, !known.isEmpty else { return }
        power()
    }

    private func power() {
        guard central == nil, !demo else { return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "me.lovearound.toys"])
    }

    /// Signed out, or the account deleted: the toys stay bonded in iOS, but
    /// this app lets go of them.
    func reset() {
        for peer in peers.values { central?.cancelPeripheralConnection(peer.peripheral) }
        peers = [:]
        near = []
        known = [:]
    }

    // MARK: The search

    func search() {
        found = []
        if demo {
            radio = .on
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                found = [Found(id: Self.demoBoard, name: DemoBoardLink.name, rssi: -48, toy: false),
                         Found(id: Self.demoToy, name: Demo.said("Браслет «Пульс»", "Pulse band"), rssi: -66, toy: true)]
            }
            return
        }
        scanning = true
        power()
        scan()
        pruning?.invalidate()
        pruning = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        }
    }

    func stopSearch() {
        scanning = false
        pruning?.invalidate()
        pruning = nil
        if central?.state == .poweredOn { central?.stopScan() }
    }

    private func scan() {
        guard scanning, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// What stopped advertising (set up by someone, out of setup mode,
    /// carried away) leaves the list.
    private func prune() {
        let fresh = found.filter { $0.seen.timeIntervalSinceNow > -8 }
        if fresh != found { found = fresh }
    }

    // MARK: A toy's link

    /// Connects, lets iOS pair, and waits for the toy's `about`.
    func pair(_ id: UUID) async throws -> [String: Any] {
        if demo {
            try? await Task.sleep(nanoseconds: 800_000_000)
            return Self.demoToyAbout
        }
        guard let central, let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else {
            throw SetupError.notFound
        }
        let peer = peers[id] ?? Peer(peripheral)
        peers[id] = peer
        peripheral.delegate = self
        if let about = peer.about, peer.ready { return about }
        // The person has iOS's pairing question to answer: a minute.
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, let self, let peer = self.peers[id], let waiting = peer.waiting else { return }
            peer.waiting = nil
            waiting.resume(throwing: SetupError.pairing)
            if peer.device == nil { self.drop(id) }
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { done in
            peer.waiting?.resume(throwing: SetupError.pairing)
            peer.waiting = done
            if peripheral.state == .connected {
                peripheral.discoverServices([Self.service, Self.batteryService])
            } else {
                central.connect(peripheral)
            }
        }
    }

    /// The toy is in the account now: this phone keeps its link.
    func adopt(_ id: UUID, as device: String) {
        guard !demo else {
            near.insert(device)
            return
        }
        known[device] = id.uuidString
        guard let peer = peers[id] else { return }
        peer.device = device
        if peer.ready { near.insert(device) }
    }

    /// A setup that was given up: let go of the link.
    func drop(_ id: UUID) {
        guard let peer = peers.removeValue(forKey: id) else { return }
        peer.waiting?.resume(throwing: SetupError.pairing)
        peer.waiting = nil
        central?.cancelPeripheralConnection(peer.peripheral)
    }

    /// Writes a message to the toy; false when it isn't near.
    @discardableResult
    func send(_ message: [String: Any], to device: String) -> Bool {
        if demo {
            // The made-up toy applies its settings at once.
            if message["type"] as? String == "settings", let rev = message["rev"] as? String {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    self.onApplied(device, rev)
                }
            }
            return true
        }
        guard let peer = peers.values.first(where: { $0.device == device }) else { return false }
        return write(message, to: peer)
    }

    @discardableResult
    private func write(_ message: [String: Any], to peer: Peer) -> Bool {
        guard peer.ready, peer.rx != nil,
              let data = try? JSONSerialization.data(withJSONObject: message), data.count <= Self.maxMessage else { return false }
        // One flag byte, then as much of the JSON as a write holds.
        let room = max(peer.peripheral.maximumWriteValueLength(for: .withResponse) - 1, 1)
        var at = 0
        while at < data.count {
            let end = min(at + room, data.count)
            peer.outbox.append(Data([end < data.count ? 0x01 : 0x00]) + data[at..<end])
            at = end
        }
        pump(peer)
        return true
    }

    /// «Отключить»: the toy erases its bond and its values, if it is near.
    /// True when it heard.
    func forget(_ device: String) -> Bool {
        let heard = send(["type": "forget"], to: device)
        guard !demo else {
            near.remove(device)
            return heard
        }
        let id = known[device].flatMap(UUID.init(uuidString:))
        known[device] = nil
        near.remove(device)
        if let id, let peer = peers[id] {
            peer.device = nil
            // After the write went out.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.drop(id)
            }
        }
        return heard
    }

    private func pump(_ peer: Peer) {
        guard !peer.writing, let rx = peer.rx, !peer.outbox.isEmpty else { return }
        peer.writing = true
        peer.peripheral.writeValue(peer.outbox.removeFirst(), for: rx, type: .withResponse)
    }

    private func reconnect() {
        guard let central, central.state == .poweredOn else { return }
        for (device, text) in known {
            guard let id = UUID(uuidString: text), let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else { continue }
            let peer = peers[id] ?? Peer(peripheral)
            peer.device = device
            peers[id] = peer
            peripheral.delegate = self
            // Never times out: the link comes up whenever the toy is near.
            if peripheral.state == .disconnected { central.connect(peripheral) }
        }
    }

    private func handle(_ peer: Peer, _ message: [String: Any]) {
        switch message["type"] as? String {
        case "about":
            var about = message
            about["type"] = nil
            peer.about = about
            if let waiting = peer.waiting {
                peer.waiting = nil
                waiting.resume(returning: about)
            }
            if let device = peer.device { onAbout(device, about) }
        case "applied":
            if let device = peer.device, let rev = message["rev"] as? String { onApplied(device, rev) }
        case "press":
            if let device = peer.device, let part = message["part"] as? String, let gesture = message["gesture"] as? String {
                onPress(device, part, gesture)
            }
        default:
            // Unknown types are skipped, so a newer toy works with this app.
            break
        }
    }

    private func lost(_ peer: Peer, failed: Bool = false) {
        // A half-received message goes with the link.
        peer.incoming = Data()
        peer.outbox = []
        peer.writing = false
        peer.ready = false
        peer.rx = nil
        if let waiting = peer.waiting, failed {
            peer.waiting = nil
            waiting.resume(throwing: SetupError.pairing)
        }
        guard let device = peer.device else { return }
        near.remove(device)
        if known[device] != nil, central?.state == .poweredOn { central?.connect(peer.peripheral) }
    }

    // MARK: Made up

    /// A demo's toys are always near.
    func demoNear(_ devices: [String]) {
        near = Set(devices)
    }

    static let demoBoard = UUID(uuidString: "00000000-0000-4000-8000-0000000000B0")!
    static let demoToy = UUID(uuidString: "00000000-0000-4000-8000-0000000000A0")!
    static let demoToyAbout: [String: Any] = [
        "proto": 1, "model": "pulse-band", "firmware": "1.0.3", "wants": ["receive"],
        "parts": [
            ["id": "buzz", "kind": "vibration", "settings": ["on", "strength", "pattern"]],
            ["id": "led", "kind": "light", "settings": ["on", "color", "duration"]],
        ],
    ]
}

extension ToyCenter: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            radio = .on
            reconnect()
            scan()
        case .poweredOff:
            radio = .off
            near = []
        case .unauthorized:
            radio = .denied
        case .unsupported:
            radio = .unsupported
        default:
            radio = .unknown
        }
    }

    /// iOS started the app again for a toy (a press, the link coming back).
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        let mine = known
        for peripheral in restored {
            guard let device = mine.first(where: { $0.value == peripheral.identifier.uuidString })?.key else { continue }
            let peer = Peer(peripheral)
            peer.device = device
            peers[peripheral.identifier] = peer
            peripheral.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        // 127: iOS couldn't measure it.
        guard scanning, rssi != 127, rssi >= Self.nearEnough else { return }
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let toy = services.contains(Self.service)
        guard toy || name.hasPrefix(ESPBoardLink.namePrefix) else { return }
        // A toy already this phone's is not waiting to be set up.
        if toy, known.values.contains(peripheral.identifier.uuidString) { return }
        let entry = Found(id: peripheral.identifier, name: name.isEmpty ? "Love Around" : name, rssi: rssi, toy: toy)
        if let i = found.firstIndex(where: { $0.id == entry.id }) {
            // The list doesn't jump with every packet: only a real change.
            if found[i].name != entry.name || found[i].veryNear != entry.veryNear || found[i].toy != toy {
                found[i] = entry
            } else {
                found[i].seen = entry.seen
            }
        } else {
            found.append(entry)
            if toy {
                // Kept, or CoreBluetooth forgets the peripheral before the tap.
                peers[peripheral.identifier] = peers[peripheral.identifier] ?? Peer(peripheral)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.service, Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let peer = peers[peripheral.identifier] { lost(peer, failed: true) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let peer = peers[peripheral.identifier] { lost(peer, failed: true) }
    }
}

extension ToyCenter: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let peer = peers[peripheral.identifier] else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            lost(peer, failed: true)
            return
        }
        peripheral.discoverCharacteristics([Self.rx, Self.tx], for: service)
        if let battery = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: battery)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let peer = peers[peripheral.identifier] else { return }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.rx:
                peer.rx = characteristic
            case Self.tx:
                // The first touch of an encrypted characteristic: iOS pairs here.
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.batteryLevel:
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.tx, let peer = peers[peripheral.identifier] else { return }
        guard error == nil, characteristic.isNotifying else {
            // Not the bonded phone, or the pairing was turned down.
            lost(peer, failed: true)
            if peer.device == nil { central?.cancelPeripheralConnection(peripheral) }
            return
        }
        peer.ready = true
        if let device = peer.device {
            near.insert(device)
            onNear(device)
        }
        // The toy says `about` by itself on a subscribe; one that kept quiet
        // is asked.
        let id = peripheral.identifier
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, let peer = self.peers[id], peer.ready, peer.about == nil else { return }
            self.write(["type": "about"], to: peer)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let peer = peers[peripheral.identifier], let value = characteristic.value, !value.isEmpty else { return }
        if characteristic.uuid == Self.batteryLevel {
            if let device = peer.device { onBattery(device, min(Int(value[value.startIndex]), 100)) }
            return
        }
        guard characteristic.uuid == Self.tx else { return }
        peer.incoming.append(value.dropFirst())
        if peer.incoming.count > Self.maxMessage {
            peer.incoming = Data()
            return
        }
        guard value[value.startIndex] == 0x00 else { return }
        let whole = peer.incoming
        peer.incoming = Data()
        if let message = (try? JSONSerialization.jsonObject(with: whole)) as? [String: Any] {
            handle(peer, message)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.rx, let peer = peers[peripheral.identifier] else { return }
        peer.writing = false
        if error != nil {
            // The rest of a message that didn't go is no use.
            peer.outbox = []
            return
        }
        pump(peer)
    }
}
