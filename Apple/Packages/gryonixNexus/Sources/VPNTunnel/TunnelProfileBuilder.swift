import Foundation
import ServiceCatalog
import VPNProfile

public enum TunnelProfileBuilder {
    public struct Built: Sendable {
        public let profile: TunnelProfile
        public let secret: String
    }

    /// Why a configuration did not become a tunnel
    public enum Failure: Error, Equatable {
        case protocolNotCarried(ServiceID)
        case unreadable(WireGuardQuickConfig.ParseError?)
        case unreadableLink(ProxyLinkConfig.ParseError)
        /// An `.ovpn` that could not be taken apart
        case unreadableProfile(OpenVPNProfileConfig.ParseError?)
    }

    public static func build(text: String,
                             protocolID: ServiceID,
                             serverID: UUID,
                             serverName: String,
                             deviceID: String,
                             deviceName: String,
                             reusing existing: TunnelProfile? = nil,
                             now: Date = Date()) throws -> Built {
        guard let datapath = TunnelCapableProtocols.datapath(for: protocolID) else {
            throw Failure.protocolNotCarried(protocolID)
        }
        let facts: Facts
        switch datapath {
        case .wireGuardKit: facts = try wireGuard(text)
        case .xray: facts = try proxyLink(text, protocolID: protocolID)
        case .openVPN: facts = try openVPN(text)
        }

        let profile = TunnelProfile(
            id: existing?.id ?? UUID(),
            serverID: serverID,
            serverName: serverName,
            protocolID: protocolID,
            deviceID: deviceID,
            deviceName: deviceName,
            endpoint: facts.endpoint,
            addresses: facts.addresses,
            dns: facts.dns,
            allowedIPs: facts.allowedIPs,
            mtu: facts.mtu,
            isObfuscated: facts.isObfuscated,
            createdAt: existing?.createdAt ?? now)
        return Built(profile: profile, secret: facts.secret)
    }

    public static func canCarry(text: String, protocolID: ServiceID) -> Bool {
        guard let datapath = TunnelCapableProtocols.datapath(for: protocolID),
              TunnelCapableProtocols.integrated.contains(datapath) else {
            return false
        }
        do {
            switch datapath {
            case .wireGuardKit: _ = try wireGuard(text)
            case .xray: _ = try proxyLink(text, protocolID: protocolID)
            case .openVPN: _ = try openVPN(text)
            }
            return true
        } catch {
            return false
        }
    }

    /// What a profile needs, whichever shape the configuration came in
    private struct Facts {
        var endpoint: String
        var addresses: [String] = []
        var dns: [String] = []
        var allowedIPs: [String] = []
        var mtu: Int?
        var isObfuscated = false
        var secret: String
    }

    private static func wireGuard(_ text: String) throws -> Facts {
        let config: WireGuardQuickConfig
        do {
            config = try WireGuardQuickConfig(parsing: text)
        } catch {
            throw Failure.unreadable(error as? WireGuardQuickConfig.ParseError)
        }
        return Facts(endpoint: config.endpoint,
                     addresses: config.addresses,
                     dns: config.dns,
                     allowedIPs: config.allowedIPs,
                     mtu: config.mtu,
                     isObfuscated: config.isObfuscated,
                     secret: config.rawText)
    }

    /// Shadowsocks and Xray Reality, which arrive as ONE LINE
    private static func proxyLink(_ text: String, protocolID: ServiceID) throws -> Facts {
        let kind: ProxyLinkConfig.Kind = protocolID == .shadowsocks ? .shadowsocks : .vless
        let link: ProxyLinkConfig
        do {
            link = try ProxyLinkConfig(parsing: text, kind: kind)
        } catch let error as ProxyLinkConfig.ParseError {
            throw Failure.unreadableLink(error)
        }
        return Facts(endpoint: link.endpoint,
                     allowedIPs: ["0.0.0.0/0", "::/0"],
                     secret: link.rawText)
    }

    private static func openVPN(_ text: String) throws -> Facts {
        let config: OpenVPNProfileConfig
        do {
            config = try OpenVPNProfileConfig(parsing: text)
        } catch {
            throw Failure.unreadableProfile(error as? OpenVPNProfileConfig.ParseError)
        }
        guard let endpoint = config.remoteEndpoint else {
            throw Failure.unreadableProfile(.noRemote)
        }
        return Facts(endpoint: endpoint,
                     allowedIPs: ["0.0.0.0/0", "::/0"],
                     secret: config.rawText)
    }
}
