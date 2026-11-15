import Darwin
import Foundation

/// This device's IPv4 addresses on Wi-Fi, Ethernet or a hotspot
public enum QuickTransferAddresses {
    static let interfacePrefixes = ["en", "bridge", "ap"]
    static let limit = 4

    public static func current() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [(name: String, address: String)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            if let pair = ipv4(entry.pointee) { found.append(pair) }
        }
        return ordered(found)
    }

    static func ipv4(_ entry: ifaddrs) -> (name: String, address: String)? {
        let flags = Int32(entry.ifa_flags)
        guard let socket = entry.ifa_addr, socket.pointee.sa_family == UInt8(AF_INET),
              flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { return nil }
        let name = String(cString: entry.ifa_name)
        guard interfacePrefixes.contains(where: name.hasPrefix) else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(socket, socklen_t(socket.pointee.sa_len), &host, socklen_t(host.count),
                          nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        let address = String(cString: host)
        return address.hasPrefix("169.254.") ? nil : (name, address)
    }

    /// Wi-Fi first, no repeats, a few at most
    static func ordered(_ found: [(name: String, address: String)]) -> [String] {
        let sorted = found.sorted { lhs, rhs in
            (lhs.name == "en0" ? 0 : 1, lhs.name) < (rhs.name == "en0" ? 0 : 1, rhs.name)
        }
        var seen = Set<String>()
        return sorted.map(\.address).filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }
}
