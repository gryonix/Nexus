/// Identifier of a managed self-hosted service. A struct rather than an enum
/// so new services can be added without breaking stored deployments
/// (mirrors the RecipeIdentifier pattern in gryonixNexusCore).
public struct ServiceID: RawRepresentable, Sendable, Hashable, Codable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let mailcow = ServiceID(rawValue: "mailcow")
    public static let mailu = ServiceID(rawValue: "mailu")
    public static let dockerMailserver = ServiceID(rawValue: "docker-mailserver")
    public static let vaultwarden = ServiceID(rawValue: "vaultwarden")
    public static let psono = ServiceID(rawValue: "psono")
    public static let passbolt = ServiceID(rawValue: "passbolt")
    public static let nextcloud = ServiceID(rawValue: "nextcloud")
    public static let seafile = ServiceID(rawValue: "seafile")
    public static let immich = ServiceID(rawValue: "immich")
    public static let forgejo = ServiceID(rawValue: "forgejo")
    public static let gitlab = ServiceID(rawValue: "gitlab")
    public static let jellyfin = ServiceID(rawValue: "jellyfin")
    public static let adguardHome = ServiceID(rawValue: "adguard-home")
    public static let pihole = ServiceID(rawValue: "pihole")
    public static let homepage = ServiceID(rawValue: "homepage")
    public static let authelia = ServiceID(rawValue: "authelia")
    public static let headscale = ServiceID(rawValue: "headscale")
    public static let cloudflared = ServiceID(rawValue: "cloudflared")
    public static let photoprism = ServiceID(rawValue: "photoprism")
    public static let wireguardVPN = ServiceID(rawValue: "wireguard-vpn")
    public static let amneziaWG = ServiceID(rawValue: "amnezia-wg")
    public static let shadowsocks = ServiceID(rawValue: "shadowsocks")
    public static let xrayReality = ServiceID(rawValue: "xray-reality")
    public static let openVPN = ServiceID(rawValue: "openvpn")
    public static let vpnPanel = ServiceID(rawValue: "vpn-panel")
    /// The server's own membership of the mesh it hosts
    public static let tailscaleNode = ServiceID(rawValue: "tailscale-node")

    /// The local model engine
    public static let ollama = ServiceID(rawValue: "ollama")
    public static let openWebUI = ServiceID(rawValue: "open-webui")
    public static let liteLLM = ServiceID(rawValue: "litellm")

    public static let anythingLLM = ServiceID(rawValue: "anythingllm")
    public static let qdrant = ServiceID(rawValue: "qdrant")
    public static let searxng = ServiceID(rawValue: "searxng")
    /// The assistant that answers in somebody's messengers
    public static let openclaw = ServiceID(rawValue: "openclaw")

    /// The automation engine — "when this happens, do that"
    public static let n8n = ServiceID(rawValue: "n8n")

    /// The smart-home hub
    public static let homeAssistant = ServiceID(rawValue: "home-assistant")
    /// The MQTT broker the hub's devices talk over
    public static let mosquitto = ServiceID(rawValue: "mosquitto")
    /// Zigbee devices, through a stick on the machine
    public static let zigbee2MQTT = ServiceID(rawValue: "zigbee2mqtt")

    /// The hub's own add-ons: never offered, and never installed, alone
    public static let smartHomeAddOns: Set<ServiceID> = [.mosquitto, .zigbee2MQTT]

    /// Services that need a MODEL to be useful at all
    public static let modelConsumers: Set<ServiceID> = [.openWebUI, .anythingLLM, .openclaw]

    public static let minecraftJava = ServiceID(rawValue: "minecraft-java")
    public static let minecraftBedrock = ServiceID(rawValue: "minecraft-bedrock")
    public static let craftyController = ServiceID(rawValue: "crafty-controller")

    /// The game engines
    public static let gameServers: Set<ServiceID> = [.minecraftJava, .minecraftBedrock]

    /// The user-selectable VPN protocols
    public static let vpnProtocols: Set<ServiceID> = [
        .wireguardVPN, .amneziaWG, .shadowsocks, .xrayReality, .openVPN
    ]

    public static func < (lhs: ServiceID, rhs: ServiceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
