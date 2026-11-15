import Foundation
import ServerControl
#if canImport(UIKit)
import UIKit
#endif

/// Reads the code, reaches the sender, takes the servers in
@MainActor
final class QuickTransferReceiveModel: ObservableObject {
    enum Phase: Equatable {
        case scanning
        case connecting
        case confirming(code: String)
        case receiving
        case received(names: [String])
        case failed(String)
    }

    @Published private(set) var phase: Phase = .scanning

    private let deliver: @MainActor ([DeploymentTransfer]) -> [String]
    private var task: Task<Void, Never>?

    init(deliver: @escaping @MainActor ([DeploymentTransfer]) -> [String]) {
        self.deliver = deliver
    }

    /// A scanned text; true when it is a transfer code
    @discardableResult
    func scanned(_ text: String) -> Bool {
        guard phase == .scanning, let ticket = QuickTransferTicket(text: text) else { return false }
        phase = .connecting
        task = Task { await run(ticket) }
        return true
    }

    func retry() {
        task?.cancel()
        phase = .scanning
    }

    func stop() { task?.cancel() }

    private func run(_ ticket: QuickTransferTicket) async {
        do {
            let link = try await QuickTransferRace.first(of: Self.attempts(for: ticket), timeout: 25)
            let channel = QuickTransferChannel(link: link, key: ticket.key, role: .receiver)
            defer { Self.closeSoon(channel) }
            phase = .confirming(code: try await QuickTransferFlow.knock(channel, device: Self.deviceName))
            try await QuickTransferFlow.awaitAnswer(channel)
            phase = .receiving
            let texts = try await QuickTransferFlow.collect(channel)
            let transfers = try texts.map { try DeploymentTransferService.decode(Data($0.utf8)) }
            phase = .received(names: deliver(transfers))
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// The network first; Bluetooth joins a moment later
    static func attempts(for ticket: QuickTransferTicket) -> [QuickTransferRace.Attempt] {
        var attempts: [QuickTransferRace.Attempt] = []
        if !ticket.addresses.isEmpty, ticket.port != 0 {
            attempts.append {
                try await QuickTransferTCPLink.connectFirst(to: ticket.addresses, port: ticket.port, timeout: 6)
            }
        }
        attempts.append {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return try await QuickTransferBluetoothReceiver.connect(service: ticket.bluetoothService)
        }
        return attempts
    }

    /// Lets the last reply leave before the link goes
    private static func closeSoon(_ channel: QuickTransferChannel) {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            channel.close()
        }
    }

    static func message(for error: Error) -> String {
        switch error as? QuickTransferError {
        case .declined:
            return UIL10n.string("The other device declined the transfer.")
        case .notOurs:
            return UIL10n.string("This code belongs to another transfer. Scan the code that is on screen now.")
        case .timedOut, .closed:
            return UIL10n.string("The other device could not be reached. Keep both devices close with Bluetooth on, or join the same Wi-Fi.")
        case .unexpected, .tooLarge:
            return UIL10n.string("The transfer stopped before the servers arrived. Try again, or export them to a file.")
        case nil:
            return UIL10n.string("Failed to import the server: %@", error.localizedDescription)
        }
    }

    static var deviceName: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }
}
