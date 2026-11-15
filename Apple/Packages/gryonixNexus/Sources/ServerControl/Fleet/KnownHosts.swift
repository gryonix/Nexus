import CryptoKit
import Foundation

public struct KnownHostKey: Identifiable, Equatable, Sendable {
    public enum Owner: Equatable, Sendable {
        case node(SSHHostID)
        case bastion(String)
    }

    public let serverName: String
    public let machineName: String
    public let endpoint: String
    public let keyType: String
    public let fingerprint: String
    public let owner: Owner
    public let id: String

    public init(serverName: String, machineName: String, endpoint: String, keyType: String,
                fingerprint: String, owner: Owner, id: String) {
        self.serverName = serverName
        self.machineName = machineName
        self.endpoint = endpoint
        self.keyType = keyType
        self.fingerprint = fingerprint
        self.owner = owner
        self.id = id
    }
}

public enum KnownHosts {
    /// "ssh-ed25519 AAAA…" as the type and its SHA256 fingerprint
    public static func describe(_ pin: String) -> (keyType: String, fingerprint: String)? {
        let parts = pin.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])), !blob.isEmpty else { return nil }
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return (String(parts[0]), "SHA256:\(digest)")
    }

    public static func entries(for deployment: Deployment, pin: (SSHHostID) -> String?) -> [KnownHostKey] {
        deployment.nodes.compactMap { node in
            guard let stored = pin(node.sshHost), let key = describe(stored) else { return nil }
            return KnownHostKey(serverName: deployment.name, machineName: node.name,
                                endpoint: "\(node.endpoint.host):\(node.endpoint.port)",
                                keyType: key.keyType, fingerprint: key.fingerprint,
                                owner: .node(node.sshHost), id: "\(deployment.id)/\(node.id)")
        }
    }

    /// Jump hosts typed in by hand, keyed by their host:port
    public static func bastionEntries(for deployment: Deployment, endpoints: [String],
                                      pin: (String) -> String?) -> [KnownHostKey] {
        endpoints.compactMap { endpoint in
            guard let stored = pin(endpoint), let key = describe(stored) else { return nil }
            return KnownHostKey(serverName: deployment.name, machineName: endpoint, endpoint: endpoint,
                                keyType: key.keyType, fingerprint: key.fingerprint,
                                owner: .bastion(endpoint), id: "\(deployment.id)/bastion/\(endpoint)")
        }
    }
}
