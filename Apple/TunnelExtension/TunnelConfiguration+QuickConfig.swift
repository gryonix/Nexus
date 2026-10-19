#if canImport(WireGuardKit) && !GRYONIX_PROXY_TUNNEL
import Foundation
import Network
import VPNProfile
import WireGuardKit

enum TunnelConfigurationBuilder {
    enum Failure: LocalizedError {
        case missingPrivateKey
        case badKey(String)
        case badAddress(String, String)
        case badEndpoint(String)
        case badMTU(Int)

        var errorDescription: String? {
            switch self {
            case .missingPrivateKey:
                return "The configuration has no PrivateKey under [Interface]."
            case .badKey(let name):
                return "\(name) is not a valid WireGuard key."
            case .badAddress(let field, let value):
                return "\(field) does not name an address: \(value)"
            case .badEndpoint(let value):
                return "Endpoint does not name a host and port: \(value)"
            case .badMTU(let value):
                return "MTU is not a valid size: \(value)"
            }
        }
    }

    static func applyObfuscation(_ values: [(key: String, value: String)],
                                 to interface: inout InterfaceConfiguration) {
        for (key, value) in values {
            switch key {
            case "Jc":   interface.junkPacketCount = UInt16(value)
            case "Jmin": interface.junkPacketMinSize = UInt16(value)
            case "Jmax": interface.junkPacketMaxSize = UInt16(value)
            case "S1":   interface.initPacketJunkSize = UInt16(value)
            case "S2":   interface.responsePacketJunkSize = UInt16(value)
            case "H1":   interface.initPacketMagicHeader = value
            case "H2":   interface.responsePacketMagicHeader = value
            case "H3":   interface.underloadPacketMagicHeader = value
            case "H4":   interface.transportPacketMagicHeader = value
            default:     continue
            }
        }
    }

    static func make(from config: WireGuardQuickConfig, name: String,
                     pin: EndpointPin? = nil) throws -> TunnelConfiguration {
        guard let privateKeyText = config.interfacePrivateKey else {
            throw Failure.missingPrivateKey
        }
        guard let privateKey = PrivateKey(base64Key: privateKeyText) else {
            throw Failure.badKey("PrivateKey")
        }
        var interface = InterfaceConfiguration(privateKey: privateKey)
        interface.addresses = try config.addresses.map {
            guard let range = IPAddressRange(from: $0) else {
                throw Failure.badAddress("Address", $0)
            }
            return range
        }
        interface.dns = try config.dns.map {
            guard let server = DNSServer(from: $0) else {
                throw Failure.badAddress("DNS", $0)
            }
            return server
        }
        if let mtu = config.mtu {
            guard let size = UInt16(exactly: mtu) else { throw Failure.badMTU(mtu) }
            interface.mtu = size
        }
        applyObfuscation(config.obfuscation, to: &interface)

        guard let peerPublicKeyText = config.peerPublicKey,
              let peerPublicKey = PublicKey(base64Key: peerPublicKeyText) else {
            throw Failure.badKey("PublicKey")
        }
        var peer = PeerConfiguration(publicKey: peerPublicKey)
        if let presharedText = config.peerPresharedKey {
            guard let preshared = PreSharedKey(base64Key: presharedText) else {
                throw Failure.badKey("PresharedKey")
            }
            peer.preSharedKey = preshared
        }
        peer.allowedIPs = try config.allowedIPs.map {
            guard let range = IPAddressRange(from: $0) else {
                throw Failure.badAddress("AllowedIPs", $0)
            }
            return range
        }
        let endpointText = pin?.replacingHost(of: config.endpoint) ?? config.endpoint
        guard let endpoint = Endpoint(from: endpointText) else {
            throw Failure.badEndpoint(config.endpoint)
        }
        peer.endpoint = endpoint
        if let keepalive = config.persistentKeepalive {
            peer.persistentKeepAlive = String(keepalive)
        }

        return TunnelConfiguration(name: name, interface: interface, peers: [peer])
    }
}
#endif
