/// Paths a service's apps use, opened past the VPN guard as one.
public struct ServiceAPIGroup: Sendable, Hashable, Identifiable {
    public let id: String
    /// English; the app translates it
    public let title: String
    public let detail: String
    public let paths: [String]
}

public enum ServiceAPIGroups {
    /// The API groups one service offers, none for most
    public static func groups(for service: ServiceID) -> [ServiceAPIGroup] {
        switch service {
        case .vaultwarden:
            return [ServiceAPIGroup(id: "bitwarden-apps", title: "Bitwarden apps",
                                    detail: "Phone, desktop and browser apps sync your passwords.",
                                    paths: VaultwardenService.bitwardenAPIPaths)]
        case .mailcow:
            return [ServiceAPIGroup(id: "mail-sync", title: "Mail apps",
                                    detail: "Calendars, contacts and ActiveSync in mail apps.",
                                    paths: MailcowService.syncPaths)]
        case .n8n:
            return [ServiceAPIGroup(id: "webhooks", title: "Webhooks",
                                    detail: "Other services start your workflows.",
                                    paths: N8NService.webhookPaths)]
        default:
            return appGroups(for: service)
        }
    }

    private static func appGroups(for service: ServiceID) -> [ServiceAPIGroup] {
        switch service {
        case .nextcloud:
            return [ServiceAPIGroup(id: "nextcloud-apps", title: "Nextcloud apps",
                                    detail: "Files, calendars and contacts in the apps. Sign in once over the VPN.",
                                    paths: ["/remote.php/*", "/ocs/*", "/status.php",
                                            "/.well-known/caldav", "/.well-known/carddav"])]
        case .immich:
            return [ServiceAPIGroup(id: "immich-app", title: "Immich app",
                                    detail: "Photo backup from the phone.",
                                    paths: ["/api/*", "/.well-known/immich"])]
        case .seafile:
            return [ServiceAPIGroup(id: "seafile-apps", title: "Seafile apps",
                                    detail: "Sync clients and the mobile app.",
                                    paths: ["/api2/*", "/api/v2.1/*", "/seafhttp/*"])]
        case .openWebUI:
            return [ServiceAPIGroup(id: "api", title: "API",
                                    detail: "Programs that call your models with a key.",
                                    paths: ["/api/*", "/ollama/*"])]
        case .liteLLM:
            return [ServiceAPIGroup(id: "api", title: "API",
                                    detail: "Programs that call your models with a key.",
                                    paths: ["/v1/*", "/chat/completions", "/completions", "/embeddings", "/models"])]
        default:
            return []
        }
    }

    /// Groups whose every path is open
    public static func openGroups(of service: ServiceID, openPaths: [String]) -> Set<String> {
        let open = Set(openPaths)
        return Set(groups(for: service).filter { open.isSuperset(of: $0.paths) }.map(\.id))
    }

    /// The paths to send when these groups are open
    public static func paths(of service: ServiceID, openGroups: Set<String>, keeping current: [String]) -> [String] {
        let known = Set(groups(for: service).flatMap(\.paths))
        var result = current.filter { !known.contains($0) }
        for group in groups(for: service) where openGroups.contains(group.id) {
            result += group.paths.filter { !result.contains($0) }
        }
        return result
    }
}
