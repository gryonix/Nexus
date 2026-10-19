import Foundation

public enum ServiceDefaultHostnames {
    public struct Group: Sendable {
        /// The name the single member of this group takes
        public let shared: String
        public let own: [ServiceID: String]

        public var members: Set<ServiceID> { Set(own.keys) }
    }

    public static let groups: [Group] = [
        Group(shared: "vault", own: [
            .vaultwarden: "vaultwarden", .psono: "psono", .passbolt: "passbolt",
        ]),
        Group(shared: "files", own: [
            .nextcloud: "nextcloud", .seafile: "seafile",
        ]),
        Group(shared: "photos", own: [
            .immich: "immich", .photoprism: "photoprism",
        ]),
        Group(shared: "dns", own: [
            .adguardHome: "adguard", .pihole: "pihole",
        ]),
        Group(shared: "git", own: [
            .forgejo: "forgejo", .gitlab: "gitlab",
        ]),
        Group(shared: "ai", own: [
            .openWebUI: "openwebui", .anythingLLM: "anythingllm",
            .liteLLM: "litellm", .openclaw: "openclaw",
        ]),
    ]

    public static let sole: [ServiceID: String] = [
        .jellyfin: "media",
        .authelia: "auth",
        .homepage: "start",
        .headscale: "mesh",
        .craftyController: "mc",
        .n8n: "flows",
        .homeAssistant: "home",
        .zigbee2MQTT: "zigbee",
    ]

    public static func hostname(_ id: ServiceID, _ context: ServiceContext) -> String {
        "\(label(id, installed: context.installedServices)).\(context.domain)"
    }

    public static func label(_ id: ServiceID, installed: Set<ServiceID>) -> String {
        guard let group = groups.first(where: { $0.own[id] != nil }) else {
            return sole[id] ?? id.rawValue
        }
        let present = group.members.filter { installed.contains($0) || $0 == id }
        return present.count <= 1 ? group.shared : (group.own[id] ?? id.rawValue)
    }
}

extension ServiceDefaultHostnames {
    /// Keeps installed siblings on the names they already answer on
    public static func pinningSiblings(adding id: ServiceID, to settings: ServiceSettings,
                                       installed: Set<ServiceID>, domain: String) -> ServiceSettings {
        guard let group = groups.first(where: { $0.own[id] != nil }) else { return settings }
        var pinned = settings
        for sibling in group.members where sibling != id && installed.contains(sibling) {
            guard let path = hostnameSetting[sibling], pinned[keyPath: path].isEmpty else { continue }
            let before = label(sibling, installed: installed)
            guard before != label(sibling, installed: installed.union([id])) else { continue }
            pinned[keyPath: path] = "\(before).\(domain)"
        }
        return pinned
    }

    /// Where each grouped service keeps a hostname of its own
    static let hostnameSetting: [ServiceID: WritableKeyPath<ServiceSettings, String>] = [
        .vaultwarden: \.vaultwardenHostname, .psono: \.psonoHostname, .passbolt: \.passboltHostname,
        .nextcloud: \.nextcloudHostname, .seafile: \.seafileHostname,
        .immich: \.immichHostname, .photoprism: \.photoprismHostname,
        .adguardHome: \.adguardHostname, .pihole: \.piholeHostname,
        .forgejo: \.forgejoHostname, .gitlab: \.gitlabHostname,
        .openWebUI: \.openWebUIHostname, .anythingLLM: \.anythingLLMHostname,
        .liteLLM: \.liteLLMHostname, .openclaw: \.openclawHostname,
    ]
}
