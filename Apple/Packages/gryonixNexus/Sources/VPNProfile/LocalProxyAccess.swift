import Foundation

/// One session's loopback SOCKS5 port and login
public struct LocalProxyAccess: Equatable, Sendable {
    public let port: Int
    public let username: String
    public let password: String

    public init(port: Int, username: String, password: String) {
        self.port = port
        self.username = username
        self.password = password
    }

    public static func random() -> LocalProxyAccess {
        LocalProxyAccess(port: freeLoopbackPort(), username: token(), password: token())
    }

    private static func token() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private static func freeLoopbackPort() -> Int {
        let fallback = Int.random(in: 49152...65535)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return fallback }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
            }
        }
        return bound ? Int(UInt16(bigEndian: address.sin_port)) : fallback
    }
}
