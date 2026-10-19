import Foundation
import Network
import ServerControl
import gryonixNexusCore

/// Silence a card waits before offering a wake-up
enum WakeButtonSettings {
    static let delayKey = "wake.buttonDelay"
    static let defaultDelay = 15
    static let delays = [15, 30, 60, 120, 300, 600]

    static func title(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds < 60 ? [.second] : [.minute]
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)"
    }
}

/// Bumps whenever this device changes network
@MainActor
final class NetworkWatch: ObservableObject {
    static let shared = NetworkWatch()

    @Published private(set) var generation = 0
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { _ in
            Task { @MainActor in NetworkWatch.shared.generation += 1 }
        }
        monitor.start(queue: DispatchQueue(label: "gryonixnexus.network-watch"))
    }
}

/// Whether this device can reach a machine's local network
enum LocalNetworkCheck {
    /// nil when neither the machine's address nor network is known
    static func isOnNetwork(of node: DeploymentNode, broadcast: String?) async -> Bool? {
        let host = node.endpoint.host
        var machine: String? = WakeOnLAN.broadcastAddress(for: host) == nil ? nil : host
        if machine == nil, WakeOnLAN.isLocalNetwork(host) {
            machine = await DashboardViewModel.within(seconds: 2) { await WakeOnLAN.resolveIPv4(host) }
        }
        return WakeOnLAN.sharesNetwork(device: deviceAddresses(), machine: machine, broadcast: broadcast)
    }

    /// Every IPv4 address this device holds, with its netmask
    static func deviceAddresses() -> [WakeOnLAN.DeviceAddress] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var found: [WakeOnLAN.DeviceAddress] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  entry.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
                  let address = numeric(entry.ifa_addr), let mask = numeric(entry.ifa_netmask) else { continue }
            found.append(WakeOnLAN.DeviceAddress(address: address, netmask: mask))
        }
        return found
    }

    private static func numeric(_ pointer: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let pointer else { return nil }
        var address = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(cString: buffer)
    }
}
