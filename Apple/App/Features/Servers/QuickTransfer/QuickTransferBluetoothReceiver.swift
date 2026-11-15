import CoreBluetooth
import Foundation
import ServerControl

/// Finds the sender's session over Bluetooth and connects to it
final class QuickTransferBluetoothReceiver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate,
    QuickTransferLink, @unchecked Sendable {
    private let service: CBUUID
    private let queue = DispatchQueue(label: "quicktransfer.central")
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var inbox: CBCharacteristic?
    private var connected: CheckedContinuation<Void, Error>?
    private var written: CheckedContinuation<Void, Error>?
    private let inbound = QuickTransferInbound()

    init(service: UUID) {
        self.service = CBUUID(nsuuid: service)
    }

    /// Scans, connects and subscribes; returns once ready
    static func connect(service: UUID) async throws -> any QuickTransferLink {
        let receiver = QuickTransferBluetoothReceiver(service: service)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                receiver.queue.async {
                    receiver.connected = continuation
                    receiver.manager = CBCentralManager(delegate: receiver, queue: receiver.queue)
                }
            }
        } onCancel: {
            receiver.close()
        }
        return receiver
    }

    private func finishConnecting(_ error: Error?) {
        let pending = connected
        connected = nil
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }

    // MARK: - Central

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: central.scanForPeripherals(withServices: [service])
        case .unauthorized, .unsupported, .poweredOff: finishConnecting(QuickTransferError.closed)
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finishConnecting(QuickTransferError.closed)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        finishConnecting(QuickTransferError.closed)
        failWrite()
        inbound.finish()
    }

    // MARK: - Peripheral

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let found = peripheral.services?.first(where: { $0.uuid == service }) else {
            return finishConnecting(QuickTransferError.closed)
        }
        peripheral.discoverCharacteristics([QuickTransferBluetooth.inbox, QuickTransferBluetooth.outbox], for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        inbox = characteristics.first { $0.uuid == QuickTransferBluetooth.inbox }
        guard inbox != nil, let outbox = characteristics.first(where: { $0.uuid == QuickTransferBluetooth.outbox })
        else { return finishConnecting(QuickTransferError.closed) }
        peripheral.setNotifyValue(true, for: outbox)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        finishConnecting(error == nil && characteristic.isNotifying ? nil : QuickTransferError.closed)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == QuickTransferBluetooth.outbox, let value = characteristic.value else { return }
        inbound.append(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let pending = written
        written = nil
        if error != nil { pending?.resume(throwing: QuickTransferError.closed) } else { pending?.resume() }
    }

    private func failWrite() {
        let pending = written
        written = nil
        pending?.resume(throwing: QuickTransferError.closed)
    }

    // MARK: - Link

    func send(_ payload: Data) async throws {
        guard let peripheral, inbox != nil else { throw QuickTransferError.closed }
        let size = max(20, min(512, peripheral.maximumWriteValueLength(for: .withoutResponse)))
        for chunk in QuickTransferInbound.chunks(of: QuickTransferFrames.frame(payload), size: size) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async { self.write(chunk, answering: continuation) }
            }
        }
    }

    /// Runs on the central's queue
    private func write(_ chunk: Data, answering continuation: CheckedContinuation<Void, Error>) {
        guard let peripheral, let inbox else {
            continuation.resume(throwing: QuickTransferError.closed)
            return
        }
        written = continuation
        peripheral.writeValue(chunk, for: inbox, type: .withResponse)
    }

    func receive() async throws -> Data { try await inbound.next() }

    func close() {
        queue.async { [self] in
            manager?.stopScan()
            if let peripheral { manager?.cancelPeripheralConnection(peripheral) }
            finishConnecting(CancellationError())
            failWrite()
            inbound.finish()
        }
    }
}
