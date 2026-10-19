import Foundation

public enum WGShowParser {
    public static func parse(_ output: String) throws -> WGStatus {
        var interfaceName: String?
        var interfacePublicKey: String?
        var listeningPort: Int?
        var peers: [PeerBuilder] = []

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "interface":
                interfaceName = value
            case "peer":
                peers.append(PeerBuilder(publicKey: value))
            case "public key":
                if peers.isEmpty { interfacePublicKey = value }
            case "listening port":
                if peers.isEmpty { listeningPort = Int(value) }
            case "endpoint":
                peers.indices.last.map { peers[$0].endpoint = value }
            case "latest handshake":
                peers.indices.last.map { peers[$0].latestHandshake = value }
            case "transfer":
                peers.indices.last.map { peers[$0].transfer = value }
            case "allowed ips":
                peers.indices.last.map {
                    peers[$0].allowedIPs = value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                }
            default:
                break
            }
        }

        guard let name = interfaceName else {
            throw ServerControlError.parseFailure(
                command: "wg show",
                detail: "no 'interface:' block in output"
            )
        }
        return WGStatus(
            interface: WGInterfaceStatus(
                name: name,
                publicKey: interfacePublicKey,
                listeningPort: listeningPort
            ),
            peers: peers.map { $0.build() }
        )
    }

    private struct PeerBuilder {
        let publicKey: String
        var endpoint: String?
        var latestHandshake: String?
        var transfer: String?
        var allowedIPs: [String] = []

        func build() -> WGPeer {
            WGPeer(publicKey: publicKey, endpoint: endpoint,
                   latestHandshake: latestHandshake, transfer: transfer,
                   allowedIPs: allowedIPs)
        }
    }
}
