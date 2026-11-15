import Foundation
import ServerControl

/// Shows the code, waits for a receiver, sends the servers
@MainActor
final class QuickTransferSendModel: ObservableObject {
    enum Phase: Equatable {
        case starting
        case showing
        case asking(device: String, code: String)
        case sending(device: String)
        case sent(device: String, count: Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var ticket: QuickTransferTicket?
    @Published private(set) var modules: [[Bool]] = []

    let deployments: [Deployment]
    private let prepare: @MainActor (Deployment) async -> String?
    private var listener: QuickTransferTCPListener?
    private var bluetooth: QuickTransferBluetoothSender?
    private var peer: QuickTransferChannel?

    init(deployments: [Deployment], prepare: @escaping @MainActor (Deployment) async -> String?) {
        self.deployments = deployments
        self.prepare = prepare
    }

    /// Opens both doors and puts a fresh code on screen
    func start() async {
        closeDoors()
        peer = nil
        phase = .starting
        let port = await startListening()
        let fresh = QuickTransferTicket.fresh(port: port, addresses: port == 0 ? [] : QuickTransferAddresses.current())
        ticket = fresh
        modules = QuickTransferModules.grid(for: fresh.text)
        let bluetooth = QuickTransferBluetoothSender(service: fresh.bluetoothService) { [weak self] link in
            Task { @MainActor in self?.offer(link) }
        }
        bluetooth.start()
        self.bluetooth = bluetooth
        phase = .showing
    }

    private func startListening() async -> UInt16 {
        guard let listener = try? QuickTransferTCPListener() else { return 0 }
        self.listener = listener
        let port = try? await listener.start { [weak self] link in
            Task { @MainActor in self?.offer(link) }
        }
        return port ?? 0
    }

    private func offer(_ link: any QuickTransferLink) {
        guard peer == nil, let ticket else { return link.close() }
        let channel = QuickTransferChannel(link: link, key: ticket.key, role: .sender)
        Task {
            guard let hello = try? await QuickTransferFlow.greet(channel), peer == nil else {
                return channel.close()
            }
            peer = channel
            stopAccepting()
            phase = .asking(device: hello.device, code: hello.code)
        }
    }

    func allow() {
        guard let peer, case .asking(let device, _) = phase else { return }
        phase = .sending(device: device)
        Task {
            do {
                try await QuickTransferFlow.accept(peer)
                let servers = await preparedServers()
                guard !servers.isEmpty else { throw QuickTransferError.unexpected }
                let count = try await QuickTransferFlow.deliver(peer, servers: servers)
                phase = .sent(device: device, count: count)
            } catch {
                phase = .failed(UIL10n.string("The transfer stopped before the servers arrived. Try again, or export them to a file."))
            }
            peer.close()
        }
    }

    private func preparedServers() async -> [String] {
        var servers: [String] = []
        for deployment in deployments {
            if let text = await prepare(deployment) { servers.append(text) }
        }
        return servers
    }

    /// Refuses this device and shows a new code
    func decline() {
        if let peer { Task { await QuickTransferFlow.decline(peer) } }
        Task { await start() }
    }

    func stop() {
        closeDoors()
        peer?.close()
        peer = nil
    }

    /// Takes no one new; the chosen receiver's link stays open
    private func stopAccepting() {
        listener?.stop()
        listener = nil
        bluetooth?.stopAdvertising()
    }

    private func closeDoors() {
        stopAccepting()
        bluetooth?.stop()
        bluetooth = nil
    }
}
