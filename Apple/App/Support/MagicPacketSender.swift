import Darwin
import Foundation

enum MagicPacketSender {
    /// Several copies to every address and port
    static func sendBurst(_ packet: Data, to hosts: [String], ports: [UInt16], copies: Int = 3) -> Bool {
        var anySent = false
        for _ in 0..<copies {
            for host in hosts {
                for port in ports where send(packet, to: host, port: port) { anySent = true }
            }
        }
        return anySent
    }

    static func send(_ packet: Data, to host: String, port: UInt16) -> Bool {
        let socketHandle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketHandle >= 0 else { return false }
        defer { close(socketHandle) }

        var enabled: Int32 = 1
        guard setsockopt(socketHandle, SOL_SOCKET, SO_BROADCAST,
                         &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            return false
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return false
        }

        let sent = packet.withUnsafeBytes { bytes -> Int in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(socketHandle, bytes.baseAddress, bytes.count, 0,
                           sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == packet.count
    }
}
