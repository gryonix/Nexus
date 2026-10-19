import Foundation
import ServiceCatalog

public enum AgentServiceMapping {
    public static func serviceIDs(forAgentIDs agentIDs: [String]) -> Set<ServiceID> {
        var result = Set<ServiceID>()
        for id in agentIDs {
            switch id {
            case "mailcow": result.insert(.mailcow)
            case "mailu": result.insert(.mailu)
            case "docker-mailserver": result.insert(.dockerMailserver)
            case "vaultwarden": result.insert(.vaultwarden)
            case "nextcloud": result.insert(.nextcloud)
            case "seafile": result.insert(.seafile)
            case "psono": result.insert(.psono)
            case "passbolt": result.insert(.passbolt)
            case "immich": result.insert(.immich)
            case "forgejo": result.insert(.forgejo)
            case "gitlab": result.insert(.gitlab)
            case "jellyfin": result.insert(.jellyfin)
            case "photoprism": result.insert(.photoprism)
            case "adguard-home": result.insert(.adguardHome)
            case "pihole": result.insert(.pihole)
            case "homepage": result.insert(.homepage)
            case "authelia": result.insert(.authelia)
            case "headscale": result.insert(.headscale)
            case "tailscale-node": result.insert(.tailscaleNode)
            case "cloudflared": result.insert(.cloudflared)
            case "minecraft-java": result.insert(.minecraftJava)
            case "minecraft-bedrock": result.insert(.minecraftBedrock)
            case "crafty-controller": result.insert(.craftyController)
            case "open-webui": result.insert(.openWebUI)
            case "ollama": result.insert(.ollama)
            case "litellm": result.insert(.liteLLM)
            case "n8n": result.insert(.n8n)
            case "home-assistant": result.insert(.homeAssistant)
            case "mosquitto": result.insert(.mosquitto)
            case "zigbee2mqtt": result.insert(.zigbee2MQTT)
            case "anythingllm": result.insert(.anythingLLM)
            case "qdrant": result.insert(.qdrant)
            case "searxng": result.insert(.searxng)
            case "openclaw": result.insert(.openclaw)
            case "vpn": result.insert(.vpnPanel)
            default: break // unknown ids are surfaced via Discover notes, not services
            }
        }
        return result
    }

    public static func serviceIDs(forAgentServices services: [(id: String, containerNames: [String])]) -> Set<ServiceID> {
        var result = serviceIDs(forAgentIDs: services.map(\.id))
        for service in services where service.id == "vpn" {
            result.formUnion(vpnProtocols(runningContainers: service.containerNames))
        }
        return result
    }

    /// Container name → protocol, for the four engines that run one
    private static let protocolContainers: [String: ServiceID] = [
        "awgvpn": .amneziaWG,
        "openvpn": .openVPN,
        "shadowsocks": .shadowsocks,
        "xray": .xrayReality
    ]

    static func vpnProtocols(runningContainers names: [String]) -> Set<ServiceID> {
        var found = Set<ServiceID>()
        for name in names {
            if let id = protocolContainers[name] { found.insert(id) }
        }
        if names.contains("vpnpanel") && found.isEmpty { found.insert(.wireguardVPN) }
        return found
    }

    public static func agentID(for serviceID: ServiceID) -> String? {
        if serviceID == .vpnPanel || ServiceID.vpnProtocols.contains(serviceID) { return "vpn" }

        switch serviceID {
        case .mailcow, .mailu, .dockerMailserver, .vaultwarden, .nextcloud, .seafile, .psono, .passbolt,
             .immich, .forgejo, .gitlab, .jellyfin, .photoprism, .adguardHome, .pihole, .headscale,
             .cloudflared, .tailscaleNode, .homepage, .authelia,
             .minecraftJava, .minecraftBedrock, .craftyController,
             .openWebUI, .ollama, .liteLLM, .n8n, .anythingLLM, .qdrant, .searxng, .openclaw,
             .homeAssistant, .mosquitto, .zigbee2MQTT:
            return serviceID.rawValue
        default: return nil
        }
    }
}
