import CoreBluetooth
import Foundation
import ServerControl

/// Characteristic numbers both platforms use
enum QuickTransferBluetooth {
    static let inbox = CBUUID(string: "7F3A0001-9C4B-4E8B-A1D2-3B6C8E5F0A11")
    static let outbox = CBUUID(string: "7F3A0002-9C4B-4E8B-A1D2-3B6C8E5F0A11")
}

#if os(tvOS)
/// The TV sends nothing over Bluetooth
final class QuickTransferBluetoothSender: @unchecked Sendable {
    init(service: UUID, onLink: @escaping @Sendable (any QuickTransferLink) -> Void) {}
    func start() {}
    func stopAdvertising() {}
    func stop() {}
}
#else
final class QuickTransferBluetoothSender: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    private let service: CBUUID
    private let onLink: @Sendable (any QuickTransferLink) -> Void
    private let queue = DispatchQueue(label: "quicktransfer.peripheral")
    private var manager: CBPeripheralManager?
    private var outbox: CBMutableCharacteristic?
    private var links: [UUID: QuickTransferPeripheralLink] = [:]
    private var accepting = true

    init(service: UUID, onLink: @escaping @Sendable (any QuickTransferLink) -> Void) {
        self.service = CBUUID(nsuuid: service)
        self.onLink = onLink
    }

    func start() {
        queue.async { [self] in
            manager = CBPeripheralManager(delegate: self, queue: queue)
        }
    }

    /// Takes no one new; the chosen receiver stays connected
    func stopAdvertising() {
        queue.async { [self] in
            accepting = false
            manager?.stopAdvertising()
        }
    }

    func stop() {
        queue.async { [self] in
            links.values.forEach { $0.finish() }
            links.removeAll()
            manager?.stopAdvertising()
            manager?.removeAllServices()
            manager?.delegate = nil
            manager = nil
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        let inbox = CBMutableCharacteristic(type: QuickTransferBluetooth.inbox, properties: [.write],
                                            value: nil, permissions: [.writeable])
        let outbox = CBMutableCharacteristic(type: QuickTransferBluetooth.outbox, properties: [.notify],
                                             value: nil, permissions: [.readable])
        let session = CBMutableService(type: service, primary: true)
        session.characteristics = [inbox, outbox]
        self.outbox = outbox
        peripheral.add(session)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [self.service]])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        guard accepting, let outbox, characteristic.uuid == QuickTransferBluetooth.outbox,
              links[central.identifier] == nil else { return }
        let link = QuickTransferPeripheralLink(manager: peripheral, central: central,
                                               outbox: outbox, queue: queue)
        links[central.identifier] = link
        onLink(link)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        links.removeValue(forKey: central.identifier)?.finish()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests where request.characteristic.uuid == QuickTransferBluetooth.inbox {
            if let value = request.value { links[request.central.identifier]?.deliver(value) }
        }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        links.values.forEach { $0.resumeSending() }
    }
}

/// One subscribed central, seen as a link
final class QuickTransferPeripheralLink: QuickTransferLink, @unchecked Sendable {
    private let manager: CBPeripheralManager
    private let central: CBCentral
    private let outbox: CBMutableCharacteristic
    private let queue: DispatchQueue
    private let inbound = QuickTransferInbound()
    private var waiting: CheckedContinuation<Void, Never>?
    /// About ten seconds of a receiver that takes nothing
    private static let maximumWaits = 50

    init(manager: CBPeripheralManager, central: CBCentral, outbox: CBMutableCharacteristic, queue: DispatchQueue) {
        self.manager = manager
        self.central = central
        self.outbox = outbox
        self.queue = queue
    }

    func deliver(_ bytes: Data) { inbound.append(bytes) }

    func finish() { inbound.finish() }

    func resumeSending() {
        let resume = waiting
        waiting = nil
        resume?.resume()
    }

    func send(_ payload: Data) async throws {
        let size = max(20, central.maximumUpdateValueLength)
        for chunk in QuickTransferInbound.chunks(of: QuickTransferFrames.frame(payload), size: size) {
            var tries = 0
            while !(await update(chunk)) {
                tries += 1
                if tries > Self.maximumWaits { throw QuickTransferError.closed }
                await waitUntilReady()
            }
        }
    }

    /// Resumes on the ready callback, or retries shortly anyway
    private func waitUntilReady() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.waiting = continuation
                self.queue.asyncAfter(deadline: .now() + 0.2) { self.resumeSending() }
            }
        }
    }

    private func update(_ chunk: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.manager.updateValue(chunk, for: self.outbox,
                                                                       onSubscribedCentrals: [self.central]))
            }
        }
    }

    func receive() async throws -> Data { try await inbound.next() }

    func close() { inbound.finish() }
}

#endif

/// Reassembles payloads from Bluetooth chunks
final class QuickTransferInbound: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = QuickTransferFrames()
    private let stream = AsyncThrowingStream<Data, Error>.makeStream()
    private var iterator: AsyncThrowingStream<Data, Error>.Iterator

    init() { iterator = stream.stream.makeAsyncIterator() }

    func append(_ bytes: Data) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try frames.append(bytes).forEach { stream.continuation.yield($0) }
        } catch {
            stream.continuation.finish(throwing: error)
        }
    }

    func finish() { stream.continuation.finish() }

    func next() async throws -> Data {
        guard let payload = try await iterator.next() else { throw QuickTransferError.closed }
        return payload
    }

    static func chunks(of data: Data, size: Int) -> [Data] {
        stride(from: 0, to: data.count, by: size).map { start in
            Data(data[data.startIndex + start ..< data.startIndex + min(start + size, data.count)])
        }
    }
}
