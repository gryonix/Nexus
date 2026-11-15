import Foundation

extension ServiceSettings {
    /// Copies only these services' fields from the edited settings
    public func adopting(_ edited: ServiceSettings, for ids: Set<ServiceID>) -> ServiceSettings {
        var merged = self
        for id in ids {
            if let keyPath = Self.hostnameSettings[id] { merged[keyPath: keyPath] = edited[keyPath: keyPath] }
            merged.copyAppFields(of: id, from: edited)
            merged.copyGameFields(of: id, from: edited)
            merged.copyVPNFields(of: id, from: edited)
        }
        merged.machineAtHome = machineAtHome || edited.machineAtHome
        return merged
    }

    private mutating func copyAppFields(of id: ServiceID, from edited: ServiceSettings) {
        switch id {
        case .vaultwarden: vaultwardenAllowSignups = edited.vaultwardenAllowSignups
        case .forgejo: forgejoSSHPort = edited.forgejoSSHPort
        case .gitlab: gitlabSSHPort = edited.gitlabSSHPort
        case .pihole: piholeServesNetwork = edited.piholeServesNetwork
        case .authelia: autheliaProtectedServices = edited.autheliaProtectedServices
        case .openWebUI: openWebUIAllowSignups = edited.openWebUIAllowSignups
        case .homeAssistant: homeAssistantUSBDevice = edited.homeAssistantUSBDevice
        case .shairportSync:
            shairportMode = edited.shairportMode
            shairportName = edited.shairportName
        case .uxplay: uxplayName = edited.uxplayName
        case .raspotify, .bluealsa, .upmpdcli: speakerName = edited.speakerName
        default: break
        }
    }

    private mutating func copyGameFields(of id: ServiceID, from edited: ServiceSettings) {
        switch id {
        case .minecraftJava:
            minecraftJavaVersion = edited.minecraftJavaVersion
            minecraftJavaFlavour = edited.minecraftJavaFlavour
            minecraftJavaMemoryMB = edited.minecraftJavaMemoryMB
            minecraftJavaPort = edited.minecraftJavaPort
            minecraftJavaAcceptsEULA = edited.minecraftJavaAcceptsEULA
            minecraftJavaWhitelist = edited.minecraftJavaWhitelist
            minecraftJavaOperators = edited.minecraftJavaOperators
        case .minecraftBedrock:
            minecraftBedrockVersion = edited.minecraftBedrockVersion
            minecraftBedrockPort = edited.minecraftBedrockPort
            minecraftBedrockAcceptsEULA = edited.minecraftBedrockAcceptsEULA
        default: break
        }
    }

    private mutating func copyVPNFields(of id: ServiceID, from edited: ServiceSettings) {
        switch id {
        case .wireguardVPN: wireguardVPNPort = edited.wireguardVPNPort
        case .amneziaWG: amneziaWGPort = edited.amneziaWGPort
        case .shadowsocks: shadowsocksPort = edited.shadowsocksPort
        case .xrayReality:
            xrayRealityPort = edited.xrayRealityPort
            xrayRealitySNI = edited.xrayRealitySNI
        case .openVPN: openVPNPort = edited.openVPNPort
        default: break
        }
    }
}
