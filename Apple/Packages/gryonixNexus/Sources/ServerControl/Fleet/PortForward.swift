import Foundation

/// A saved local-to-remote port forward for one server
public struct PortForward: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var deploymentID: UUID
    public var name: String
    /// Port opened on this device
    public var localPort: Int
    /// Host as the server sees it
    public var remoteHost: String
    public var remotePort: Int

    public init(id: UUID = UUID(), deploymentID: UUID, name: String = "",
                localPort: Int, remoteHost: String = "localhost", remotePort: Int) {
        self.id = id
        self.deploymentID = deploymentID
        self.name = name
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }

    public enum Problem: Equatable, Sendable {
        case localPort
        case remoteHost
        case remotePort
        case duplicateLocalPort
    }

    public var title: String {
        name.isEmpty ? "\(localPort) → \(remoteHost):\(remotePort)" : name
    }

    public var summary: String { "127.0.0.1:\(localPort) → \(remoteHost):\(remotePort)" }

    /// Unprivileged ports only
    public static func validPort(_ port: Int, allowPrivileged: Bool = false) -> Bool {
        port >= (allowPrivileged ? 1 : 1024) && port <= 65535
    }

    public func problems(among others: [PortForward]) -> [Problem] {
        var found: [Problem] = []
        if !Self.validPort(localPort) { found.append(.localPort) }
        let host = remoteHost.trimmingCharacters(in: .whitespaces)
        if host.isEmpty || host.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" }) {
            found.append(.remoteHost)
        }
        if !Self.validPort(remotePort, allowPrivileged: true) { found.append(.remotePort) }
        if others.contains(where: { $0.id != id && $0.localPort == localPort }) {
            found.append(.duplicateLocalPort)
        }
        return found
    }
}

/// Live state of one forward
public enum PortForwardState: Equatable, Sendable {
    case stopped
    case starting
    case running(connections: Int)
    case failed(String)

    public var isActive: Bool {
        switch self {
        case .starting, .running: return true
        default: return false
        }
    }
}

/// Edits on the saved list
public enum PortForwardList {
    public static func forServer(_ id: UUID, in all: [PortForward]) -> [PortForward] {
        all.filter { $0.deploymentID == id }
    }

    public static func upserting(_ forward: PortForward, into all: [PortForward]) -> [PortForward] {
        if let index = all.firstIndex(where: { $0.id == forward.id }) {
            var copy = all
            copy[index] = forward
            return copy
        }
        return all + [forward]
    }

    public static func removing(_ id: UUID, from all: [PortForward]) -> [PortForward] {
        all.filter { $0.id != id }
    }

    public static func removingServer(_ id: UUID, from all: [PortForward]) -> [PortForward] {
        all.filter { $0.deploymentID != id }
    }
}
