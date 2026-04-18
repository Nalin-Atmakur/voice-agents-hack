import Foundation
import Combine
import CoreBluetooth

struct BluetoothMeshUUIDs {
    static let service = CBUUID(string: "7B4D8C10-3A8E-4D1A-9F53-2E28D9C1A001")
    static let broadcastCharacteristic = CBUUID(string: "7B4D8C10-3A8E-4D1A-9F53-2E28D9C1A101")
    static let compactionCharacteristic = CBUUID(string: "7B4D8C10-3A8E-4D1A-9F53-2E28D9C1A102")
    static let treeConfigCharacteristic = CBUUID(string: "7B4D8C10-3A8E-4D1A-9F53-2E28D9C1A103")
}

enum PeerConnectionState: String, Equatable, Sendable {
    case connected
    case disconnected
}

struct NetworkAdvertisement: Equatable, Sendable {
    let networkID: UUID
    let networkName: String
    let openSlotCount: Int
    let requiresPIN: Bool

    init(networkID: UUID, networkName: String, openSlotCount: Int, requiresPIN: Bool) {
        self.networkID = networkID
        self.networkName = networkName
        self.openSlotCount = max(0, openSlotCount)
        self.requiresPIN = requiresPIN
    }

    init(from config: NetworkConfig) {
        self.init(
            networkID: config.networkID,
            networkName: config.networkName,
            openSlotCount: config.openSlotCount,
            requiresPIN: config.requiresPIN
        )
    }
}

struct DiscoveredNetwork: Identifiable, Equatable, Sendable {
    var id: UUID { peerID }
    let peerID: UUID
    let networkID: UUID
    let networkName: String
    let openSlotCount: Int
    let requiresPIN: Bool
}

private enum NetworkAdvertisementCodec {
    private static let schemaVersion: UInt8 = 1
    private static let requiresPINFlag: UInt8 = 1 << 0
    private static let payloadLength = 20
    private static let maxAdvertisedNameLength = 20

    static func advertisingData(for summary: NetworkAdvertisement) -> [String: Any] {
        let clampedOpenSlots = UInt16(max(0, min(summary.openSlotCount, Int(UInt16.max))))
        var payload = Data(capacity: payloadLength)
        payload.append(schemaVersion)
        payload.append(summary.requiresPIN ? requiresPINFlag : 0)
        payload.append(UInt8((clampedOpenSlots >> 8) & 0xFF))
        payload.append(UInt8(clampedOpenSlots & 0xFF))
        payload.append(uuidData(summary.networkID))

        let advertisedName = String(summary.networkName.prefix(maxAdvertisedNameLength))
        return [
            CBAdvertisementDataServiceUUIDsKey: [BluetoothMeshUUIDs.service],
            CBAdvertisementDataLocalNameKey: advertisedName,
            CBAdvertisementDataServiceDataKey: [BluetoothMeshUUIDs.service: payload]
        ]
    }

    static func decode(advertisementData: [String: Any]) -> NetworkAdvertisement? {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let payload = serviceData[BluetoothMeshUUIDs.service],
              payload.count >= payloadLength,
              payload[0] == schemaVersion else {
            return nil
        }

        let flags = payload[1]
        let openSlotCount = Int((UInt16(payload[2]) << 8) | UInt16(payload[3]))
        guard let networkID = uuid(from: payload.subdata(in: 4..<20)) else {
            return nil
        }

        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let networkName = (advertisedName?.isEmpty == false) ? advertisedName! : "TacNet Network"

        return NetworkAdvertisement(
            networkID: networkID,
            networkName: networkName,
            openSlotCount: openSlotCount,
            requiresPIN: (flags & requiresPINFlag) != 0
        )
    }

    private static func uuidData(_ uuid: UUID) -> Data {
        var rawUUID = uuid.uuid
        return withUnsafeBytes(of: &rawUUID) { Data($0) }
    }

    private static func uuid(from data: Data) -> UUID? {
        guard data.count == 16 else {
            return nil
        }

        var rawUUID: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        _ = withUnsafeMutableBytes(of: &rawUUID) { destination in
            data.copyBytes(to: destination)
        }
        return UUID(uuid: rawUUID)
    }
}

enum BluetoothMeshTransportError: Error {
    case unsupportedTreeConfigRead
    case unknownPeer
    case treeConfigUnavailable
}

enum BluetoothMeshTransportEvent: Sendable {
    case discoveredPeer(UUID)
    case discoveredNetwork(UUID, NetworkAdvertisement)
    case connectionStateChanged(UUID, PeerConnectionState)
    case receivedData(Data, from: UUID)
}

protocol BluetoothMeshTransporting: AnyObject {
    var eventHandler: ((BluetoothMeshTransportEvent) -> Void)? { get set }

    func start()
    func stop()
    func send(_ data: Data, messageType: Message.MessageType, to peerIDs: Set<UUID>)
    func configureAdvertisement(_ summary: NetworkAdvertisement?)
    func updateTreeConfigPayload(_ data: Data)
    func requestTreeConfig(from peerID: UUID, completion: @escaping (Result<Data, Error>) -> Void)
}

extension BluetoothMeshTransporting {
    func configureAdvertisement(_: NetworkAdvertisement?) {}

    func updateTreeConfigPayload(_: Data) {}

    func requestTreeConfig(from _: UUID, completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.failure(BluetoothMeshTransportError.unsupportedTreeConfigRead))
    }
}

private enum BluetoothMeshCharacteristicKind: CaseIterable {
    case broadcast
    case compaction
    case treeConfig

    var uuid: CBUUID {
        switch self {
        case .broadcast:
            return BluetoothMeshUUIDs.broadcastCharacteristic
        case .compaction:
            return BluetoothMeshUUIDs.compactionCharacteristic
        case .treeConfig:
            return BluetoothMeshUUIDs.treeConfigCharacteristic
        }
    }
}

final class BluetoothMeshService {
    typealias MessageHandler = (Message) -> Void
    typealias PeerStateHandler = (UUID, PeerConnectionState) -> Void
    typealias PeerDiscoveryHandler = (UUID) -> Void
    typealias NetworkDiscoveryHandler = (UUID, NetworkAdvertisement) -> Void

    var onMessageReceived: MessageHandler?
    var onPeerConnectionStateChanged: PeerStateHandler?
    var onPeerDiscovered: PeerDiscoveryHandler?
    var onNetworkDiscovered: NetworkDiscoveryHandler?

    private let transport: BluetoothMeshTransporting
    private let deduplicator: MessageDeduplicator
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var peerStates: [UUID: PeerConnectionState] = [:]

    private struct QueuedRelay {
        let message: Message
        let excludedPeerID: UUID?
    }
    private var relayQueue: [QueuedRelay] = []

    init(
        transport: BluetoothMeshTransporting = CoreBluetoothMeshTransport(),
        deduplicator: MessageDeduplicator = MessageDeduplicator()
    ) {
        self.transport = transport
        self.deduplicator = deduplicator
        self.transport.eventHandler = { [weak self] event in
            self?.handleTransportEvent(event)
        }
    }

    func start() {
        transport.start()
    }

    func stop() {
        transport.stop()
    }

    func publishNetwork(_ networkConfig: NetworkConfig) {
        transport.configureAdvertisement(NetworkAdvertisement(from: networkConfig))
        if let payload = try? encoder.encode(networkConfig) {
            transport.updateTreeConfigPayload(payload)
        }
        start()
    }

    func updatePublishedNetwork(_ networkConfig: NetworkConfig) {
        publishNetwork(networkConfig)
    }

    func clearPublishedNetwork() {
        transport.configureAdvertisement(nil)
        transport.updateTreeConfigPayload(Data())
    }

    func fetchNetworkConfig(from peerID: UUID, completion: @escaping (Result<NetworkConfig, Error>) -> Void) {
        transport.requestTreeConfig(from: peerID) { result in
            switch result {
            case .success(let data):
                do {
                    let decoded = try JSONDecoder().decode(NetworkConfig.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchNetworkConfig(from peerID: UUID) async throws -> NetworkConfig {
        try await withCheckedThrowingContinuation { continuation in
            fetchNetworkConfig(from: peerID) { result in
                continuation.resume(with: result)
            }
        }
    }

    func publish(_ message: Message) {
        guard message.ttl > 0 else {
            return
        }

        guard !deduplicator.isDuplicate(messageId: message.id) else {
            return
        }

        flood(message, excluding: nil)
    }

    func connectionState(for peerID: UUID) -> PeerConnectionState {
        peerStates[peerID] ?? .disconnected
    }

    var connectedPeerIDs: Set<UUID> {
        Set(
            peerStates.compactMap { peerID, state in
                state == .connected ? peerID : nil
            }
        )
    }

    var pendingRelayCount: Int {
        relayQueue.count
    }

    private func handleTransportEvent(_ event: BluetoothMeshTransportEvent) {
        switch event {
        case .discoveredPeer(let peerID):
            onPeerDiscovered?(peerID)

        case .discoveredNetwork(let peerID, let summary):
            onNetworkDiscovered?(peerID, summary)

        case .connectionStateChanged(let peerID, let state):
            peerStates[peerID] = state
            onPeerConnectionStateChanged?(peerID, state)

            if state == .connected {
                flushRelayQueue(to: peerID)
            }

        case .receivedData(let data, let sourcePeerID):
            handleIncomingData(data, from: sourcePeerID)
        }
    }

    private func handleIncomingData(_ data: Data, from sourcePeerID: UUID) {
        guard var inboundMessage = try? decoder.decode(Message.self, from: data) else {
            return
        }

        guard inboundMessage.ttl > 0 else {
            return
        }

        guard !deduplicator.isDuplicate(messageId: inboundMessage.id) else {
            return
        }

        inboundMessage.ttl -= 1
        onMessageReceived?(inboundMessage)

        guard inboundMessage.ttl > 0 else {
            return
        }

        flood(inboundMessage, excluding: sourcePeerID)
    }

    private func flood(_ message: Message, excluding excludedPeerID: UUID?) {
        var targetPeerIDs = connectedPeerIDs
        if let excludedPeerID {
            targetPeerIDs.remove(excludedPeerID)
        }

        guard !targetPeerIDs.isEmpty else {
            relayQueue.append(QueuedRelay(message: message, excludedPeerID: excludedPeerID))
            return
        }

        send(message, to: targetPeerIDs)
    }

    private func flushRelayQueue(to peerID: UUID) {
        guard connectionState(for: peerID) == .connected else {
            return
        }

        var remaining: [QueuedRelay] = []

        for item in relayQueue {
            if item.excludedPeerID == peerID {
                remaining.append(item)
                continue
            }

            send(item.message, to: [peerID])
        }

        relayQueue = remaining
    }

    private func send(_ message: Message, to peerIDs: Set<UUID>) {
        guard let data = try? encoder.encode(message) else {
            return
        }
        transport.send(data, messageType: message.type, to: peerIDs)
    }
}

final class CoreBluetoothMeshTransport: NSObject, BluetoothMeshTransporting {
    var eventHandler: ((BluetoothMeshTransportEvent) -> Void)?

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?

    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var connectingPeripheralIDs: Set<UUID> = []
    private var discoveredCharacteristicsByPeer: [UUID: [BluetoothMeshCharacteristicKind: CBCharacteristic]] = [:]
    private var subscribedCentrals: [UUID: CBCentral] = [:]

    private var hasPublishedService = false
    private var treeConfigPayload: Data = Data()
    private var advertisedNetworkSummary: NetworkAdvertisement?
    private var pendingTreeConfigReadCompletions: [UUID: [(Result<Data, Error>) -> Void]] = [:]

    private lazy var broadcastCharacteristic: CBMutableCharacteristic = {
        CBMutableCharacteristic(
            type: BluetoothMeshUUIDs.broadcastCharacteristic,
            properties: [.read, .write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
    }()

    private lazy var compactionCharacteristic: CBMutableCharacteristic = {
        CBMutableCharacteristic(
            type: BluetoothMeshUUIDs.compactionCharacteristic,
            properties: [.read, .write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
    }()

    private lazy var treeConfigCharacteristic: CBMutableCharacteristic = {
        CBMutableCharacteristic(
            type: BluetoothMeshUUIDs.treeConfigCharacteristic,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
    }()

    func start() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }

        if centralManager?.state == .poweredOn {
            startScanning()
        }
        if peripheralManager?.state == .poweredOn {
            publishServiceIfNeeded()
            startAdvertising()
        }
    }

    func stop() {
        centralManager?.stopScan()
        for peripheral in connectedPeripherals.values {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        peripheralManager?.stopAdvertising()

        for peerID in Array(pendingTreeConfigReadCompletions.keys) {
            completeTreeConfigReads(
                for: peerID,
                result: .failure(BluetoothMeshTransportError.treeConfigUnavailable)
            )
        }

        discoveredPeripherals.removeAll()
        connectingPeripheralIDs.removeAll()
        connectedPeripherals.removeAll()
        discoveredCharacteristicsByPeer.removeAll()
        subscribedCentrals.removeAll()
    }

    func send(_ data: Data, messageType: Message.MessageType, to peerIDs: Set<UUID>) {
        let characteristicKind = characteristicKind(for: messageType)

        for peerID in peerIDs {
            if let peripheral = connectedPeripherals[peerID],
               let characteristic = discoveredCharacteristicsByPeer[peerID]?[characteristicKind] {
                peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
                continue
            }

            if let central = subscribedCentrals[peerID],
               let peripheralManager {
                let localCharacteristic = localCharacteristic(for: characteristicKind)
                _ = peripheralManager.updateValue(data, for: localCharacteristic, onSubscribedCentrals: [central])
            }
        }
    }

    func configureAdvertisement(_ summary: NetworkAdvertisement?) {
        advertisedNetworkSummary = summary
        guard peripheralManager?.state == .poweredOn else {
            return
        }
        startAdvertising()
    }

    func updateTreeConfigPayload(_ data: Data) {
        treeConfigPayload = data
    }

    func requestTreeConfig(from peerID: UUID, completion: @escaping (Result<Data, Error>) -> Void) {
        pendingTreeConfigReadCompletions[peerID, default: []].append(completion)

        if centralManager == nil || peripheralManager == nil {
            start()
        }

        guard let peripheral = connectedPeripherals[peerID] ?? discoveredPeripherals[peerID] else {
            completeTreeConfigReads(for: peerID, result: .failure(BluetoothMeshTransportError.unknownPeer))
            return
        }

        peripheral.delegate = self
        if let characteristic = discoveredCharacteristicsByPeer[peerID]?[.treeConfig] {
            peripheral.readValue(for: characteristic)
            return
        }

        if connectedPeripherals[peerID] == nil,
           let centralManager,
           centralManager.state == .poweredOn,
           !connectingPeripheralIDs.contains(peerID) {
            connectingPeripheralIDs.insert(peerID)
            centralManager.connect(peripheral, options: nil)
        }

        peripheral.discoverServices([BluetoothMeshUUIDs.service])
    }

    private func startScanning() {
        centralManager?.scanForPeripherals(
            withServices: [BluetoothMeshUUIDs.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func startAdvertising() {
        guard let peripheralManager else {
            return
        }

        peripheralManager.stopAdvertising()
        if let advertisedNetworkSummary {
            peripheralManager.startAdvertising(NetworkAdvertisementCodec.advertisingData(for: advertisedNetworkSummary))
        } else {
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [BluetoothMeshUUIDs.service]
            ])
        }
    }

    private func publishServiceIfNeeded() {
        guard !hasPublishedService else {
            return
        }

        let service = CBMutableService(type: BluetoothMeshUUIDs.service, primary: true)
        service.characteristics = [
            broadcastCharacteristic,
            compactionCharacteristic,
            treeConfigCharacteristic
        ]

        peripheralManager?.add(service)
        hasPublishedService = true
    }

    private func characteristicKind(for messageType: Message.MessageType) -> BluetoothMeshCharacteristicKind {
        switch messageType {
        case .compaction:
            return .compaction
        default:
            return .broadcast
        }
    }

    private func localCharacteristic(for kind: BluetoothMeshCharacteristicKind) -> CBMutableCharacteristic {
        switch kind {
        case .broadcast:
            return broadcastCharacteristic
        case .compaction:
            return compactionCharacteristic
        case .treeConfig:
            return treeConfigCharacteristic
        }
    }

    private func attemptTreeConfigRead(for peerID: UUID) {
        guard pendingTreeConfigReadCompletions[peerID] != nil,
              let peripheral = connectedPeripherals[peerID],
              let treeConfigCharacteristic = discoveredCharacteristicsByPeer[peerID]?[.treeConfig] else {
            return
        }

        peripheral.readValue(for: treeConfigCharacteristic)
    }

    private func completeTreeConfigReads(for peerID: UUID, result: Result<Data, Error>) {
        guard let completions = pendingTreeConfigReadCompletions.removeValue(forKey: peerID) else {
            return
        }

        completions.forEach { completion in
            completion(result)
        }
    }
}

extension CoreBluetoothMeshTransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            return
        }
        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        eventHandler?(.discoveredPeer(peripheral.identifier))
        if let advertisement = NetworkAdvertisementCodec.decode(advertisementData: advertisementData) {
            eventHandler?(.discoveredNetwork(peripheral.identifier, advertisement))
        }

        if connectedPeripherals[peripheral.identifier] == nil,
           !connectingPeripheralIDs.contains(peripheral.identifier) {
            connectingPeripheralIDs.insert(peripheral.identifier)
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectingPeripheralIDs.remove(peripheral.identifier)
        connectedPeripherals[peripheral.identifier] = peripheral
        eventHandler?(.connectionStateChanged(peripheral.identifier, .connected))

        peripheral.delegate = self
        peripheral.discoverServices([BluetoothMeshUUIDs.service])
        attemptTreeConfigRead(for: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectingPeripheralIDs.remove(peripheral.identifier)
        eventHandler?(.connectionStateChanged(peripheral.identifier, .disconnected))
        completeTreeConfigReads(
            for: peripheral.identifier,
            result: .failure(error ?? BluetoothMeshTransportError.treeConfigUnavailable)
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectingPeripheralIDs.remove(peripheral.identifier)
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        discoveredCharacteristicsByPeer.removeValue(forKey: peripheral.identifier)
        eventHandler?(.connectionStateChanged(peripheral.identifier, .disconnected))
        completeTreeConfigReads(
            for: peripheral.identifier,
            result: .failure(error ?? BluetoothMeshTransportError.treeConfigUnavailable)
        )
    }
}

extension CoreBluetoothMeshTransport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            return
        }

        peripheral.services?
            .filter { $0.uuid == BluetoothMeshUUIDs.service }
            .forEach { service in
                peripheral.discoverCharacteristics(BluetoothMeshCharacteristicKind.allCases.map(\.uuid), for: service)
            }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            return
        }

        var map: [BluetoothMeshCharacteristicKind: CBCharacteristic] = [:]

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case BluetoothMeshUUIDs.broadcastCharacteristic:
                map[.broadcast] = characteristic
            case BluetoothMeshUUIDs.compactionCharacteristic:
                map[.compaction] = characteristic
            case BluetoothMeshUUIDs.treeConfigCharacteristic:
                map[.treeConfig] = characteristic
            default:
                break
            }

            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        discoveredCharacteristicsByPeer[peripheral.identifier] = map
        attemptTreeConfigRead(for: peripheral.identifier)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == BluetoothMeshUUIDs.treeConfigCharacteristic,
           pendingTreeConfigReadCompletions[peripheral.identifier] != nil {
            if let error {
                completeTreeConfigReads(for: peripheral.identifier, result: .failure(error))
            } else if let value = characteristic.value {
                completeTreeConfigReads(for: peripheral.identifier, result: .success(value))
            } else {
                completeTreeConfigReads(
                    for: peripheral.identifier,
                    result: .failure(BluetoothMeshTransportError.treeConfigUnavailable)
                )
            }
            return
        }

        guard error == nil, let value = characteristic.value else {
            return
        }

        eventHandler?(.receivedData(value, from: peripheral.identifier))
    }
}

extension CoreBluetoothMeshTransport: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            return
        }

        publishServiceIfNeeded()
        startAdvertising()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            return
        }
        startAdvertising()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == BluetoothMeshUUIDs.treeConfigCharacteristic else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
            return
        }

        guard request.offset <= treeConfigPayload.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }

        request.value = treeConfigPayload.subdata(in: request.offset..<treeConfigPayload.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let value = request.value else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                continue
            }

            if request.characteristic.uuid == BluetoothMeshUUIDs.treeConfigCharacteristic {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }

            eventHandler?(.receivedData(value, from: request.central.identifier))
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscribedCentrals[central.identifier] = central
        eventHandler?(.connectionStateChanged(central.identifier, .connected))
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscribedCentrals.removeValue(forKey: central.identifier)
        eventHandler?(.connectionStateChanged(central.identifier, .disconnected))
    }
}

enum TreeSyncConvergenceResult: Equatable {
    case adoptedInitial(version: Int)
    case replacedWithHigherVersion(previousVersion: Int, appliedVersion: Int)
    case ignoredStale(localVersion: Int, incomingVersion: Int)
    case ignoredDifferentNetwork(expectedNetworkID: UUID, incomingNetworkID: UUID)
}

enum TreeSyncJoinError: Error, Equatable {
    case treeConfigUnavailable
    case networkMismatch
    case pinRequired
    case invalidPIN
}

@MainActor
final class TreeSyncService: ObservableObject {
    @Published private(set) var localConfig: NetworkConfig?

    private let meshService: BluetoothMeshService

    init(meshService: BluetoothMeshService = BluetoothMeshService()) {
        self.meshService = meshService
    }

    func setLocalConfig(_ config: NetworkConfig?) {
        localConfig = config
    }

    @discardableResult
    func converge(with incoming: NetworkConfig) -> TreeSyncConvergenceResult {
        guard let localConfig else {
            self.localConfig = incoming
            return .adoptedInitial(version: incoming.version)
        }

        guard localConfig.networkID == incoming.networkID else {
            return .ignoredDifferentNetwork(
                expectedNetworkID: localConfig.networkID,
                incomingNetworkID: incoming.networkID
            )
        }

        guard incoming.version > localConfig.version else {
            return .ignoredStale(localVersion: localConfig.version, incomingVersion: incoming.version)
        }

        self.localConfig = incoming
        return .replacedWithHigherVersion(
            previousVersion: localConfig.version,
            appliedVersion: incoming.version
        )
    }

    @discardableResult
    func converge(with payload: Data) throws -> TreeSyncConvergenceResult {
        let incoming = try JSONDecoder().decode(NetworkConfig.self, from: payload)
        return converge(with: incoming)
    }

    func join(network: DiscoveredNetwork, pin: String?) async throws -> NetworkConfig {
        let remoteConfig: NetworkConfig
        do {
            remoteConfig = try await meshService.fetchNetworkConfig(from: network.peerID)
        } catch {
            throw TreeSyncJoinError.treeConfigUnavailable
        }

        guard remoteConfig.networkID == network.networkID else {
            throw TreeSyncJoinError.networkMismatch
        }

        if remoteConfig.requiresPIN {
            guard let pin, !pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TreeSyncJoinError.pinRequired
            }

            guard remoteConfig.isValidPIN(pin) else {
                throw TreeSyncJoinError.invalidPIN
            }
        }

        localConfig = remoteConfig
        return remoteConfig
    }
}

@MainActor
final class NetworkDiscoveryService: ObservableObject {
    @Published private(set) var nearbyNetworks: [DiscoveredNetwork] = []
    @Published private(set) var isScanning = false

    private let meshService: BluetoothMeshService
    private var scanTimeoutTask: Task<Void, Never>?

    init(meshService: BluetoothMeshService = BluetoothMeshService()) {
        self.meshService = meshService
    }

    deinit {
        scanTimeoutTask?.cancel()
    }

    func startScanning(timeout: TimeInterval = 10) {
        nearbyNetworks = []
        isScanning = true

        meshService.onNetworkDiscovered = { [weak self] peerID, summary in
            Task { @MainActor in
                self?.upsert(
                    DiscoveredNetwork(
                        peerID: peerID,
                        networkID: summary.networkID,
                        networkName: summary.networkName,
                        openSlotCount: summary.openSlotCount,
                        requiresPIN: summary.requiresPIN
                    )
                )
            }
        }

        meshService.start()
        scanTimeoutTask?.cancel()

        let timeoutNanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.isScanning = false
            }
        }
    }

    func stopScanning() {
        isScanning = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        meshService.onNetworkDiscovered = nil
    }

    private func upsert(_ network: DiscoveredNetwork) {
        if let index = nearbyNetworks.firstIndex(where: { $0.peerID == network.peerID }) {
            nearbyNetworks[index] = network
        } else {
            nearbyNetworks.append(network)
        }

        nearbyNetworks.sort { lhs, rhs in
            if lhs.openSlotCount == rhs.openSlotCount {
                return lhs.networkName.localizedCaseInsensitiveCompare(rhs.networkName) == .orderedAscending
            }
            return lhs.openSlotCount > rhs.openSlotCount
        }
    }
}
