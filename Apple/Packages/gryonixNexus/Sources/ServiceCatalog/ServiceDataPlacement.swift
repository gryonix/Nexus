import Foundation

extension ServiceSettings {
    /// Each service's data folders
    public static let dataFolderSettings: [ServiceID: [WritableKeyPath<ServiceSettings, String>]] = [
        .mailcow: [\.mailcowPath],
        .mailu: [\.mailuPath],
        .dockerMailserver: [\.dockerMailserverPath],
        .vaultwarden: [\.vaultwardenDataPath],
        .psono: [\.psonoPath],
        .passbolt: [\.passboltPath],
        .nextcloud: [\.nextcloudPath],
        .seafile: [\.seafilePath],
        .immich: [\.immichPath],
        .photoprism: [\.photoprismPath],
        .jellyfin: [\.jellyfinPath, \.jellyfinMediaPath],
        .forgejo: [\.forgejoPath],
        .gitlab: [\.gitlabPath],
        .minecraftJava: [\.minecraftJavaPath],
        .minecraftBedrock: [\.minecraftBedrockPath],
        .craftyController: [\.craftyPath],
        .ollama: [\.ollamaPath],
        .openWebUI: [\.openWebUIPath],
        .anythingLLM: [\.anythingLLMPath],
        .qdrant: [\.qdrantPath],
        .n8n: [\.n8nPath],
        .homeAssistant: [\.homeAssistantPath],
    ]

    /// Whether a service's data can go on another disk
    public static func keepsData(_ id: ServiceID) -> Bool {
        dataFolderSettings[id] != nil
    }

    /// Moves a service's folders under a mount, keeping their names
    public mutating func placeData(of id: ServiceID, under mount: String) {
        let root = mount.hasSuffix("/") ? String(mount.dropLast()) : mount
        for keyPath in Self.dataFolderSettings[id] ?? [] {
            let current = self[keyPath: keyPath]
            guard !current.hasPrefix(root + "/") else { continue }
            let parts = current.split(separator: "/")
            let kept = parts.count > 1 ? parts.dropFirst() : parts[...]
            self[keyPath: keyPath] = root + "/" + kept.joined(separator: "/")
        }
    }
}
