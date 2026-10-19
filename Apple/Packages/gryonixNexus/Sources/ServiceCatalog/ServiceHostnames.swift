import Foundation

extension ServiceSettings {
    /// The hostname field a service reads, by service id
    public static let hostnameSettings: [ServiceID: WritableKeyPath<ServiceSettings, String>] = [
        .vaultwarden: \.vaultwardenHostname,
        .psono: \.psonoHostname,
        .passbolt: \.passboltHostname,
        .nextcloud: \.nextcloudHostname,
        .seafile: \.seafileHostname,
        .immich: \.immichHostname,
        .photoprism: \.photoprismHostname,
        .jellyfin: \.jellyfinHostname,
        .adguardHome: \.adguardHostname,
        .pihole: \.piholeHostname,
        .authelia: \.autheliaHostname,
        .homepage: \.homepageHostname,
        .headscale: \.headscaleHostname,
        .forgejo: \.forgejoHostname,
        .gitlab: \.gitlabHostname,
        .craftyController: \.craftyHostname,
        .openWebUI: \.openWebUIHostname,
        .liteLLM: \.liteLLMHostname,
        .n8n: \.n8nHostname,
        .homeAssistant: \.homeAssistantHostname,
        .zigbee2MQTT: \.zigbee2MQTTHostname,
        .anythingLLM: \.anythingLLMHostname,
        .openclaw: \.openclawHostname,
    ]

    public static let fixedHostnameServices: Set<ServiceID> = [
        .mailcow, .mailu, .dockerMailserver, .vpnPanel,
    ]

    public mutating func applyHostnames(_ hostnames: [ServiceID: String]) {
        for (id, keyPath) in Self.hostnameSettings {
            let value = (hostnames[id] ?? "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            self[keyPath: keyPath] = value
        }
    }

    public var namedHostnames: [ServiceID: String] {
        var result: [ServiceID: String] = [:]
        for (id, keyPath) in Self.hostnameSettings where !self[keyPath: keyPath].isEmpty {
            result[id] = self[keyPath: keyPath]
        }
        return result
    }
}
