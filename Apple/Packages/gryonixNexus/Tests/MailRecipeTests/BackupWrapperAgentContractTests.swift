import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class BackupWrapperAgentContractTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    private func wrapperDirectories(in script: String) -> [String: String] {
        var found: [String: String] = [:]
        for rawLine in script.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let paren = line.firstIndex(of: ")") else { continue }
            let label = String(line[line.startIndex..<paren])
            guard !label.isEmpty,
                  label.allSatisfy({ $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" || $0 == "_" }),
                  let dirStart = line.range(of: "dir='"),
                  let dirEnd = line[dirStart.upperBound...].firstIndex(of: "'") else { continue }
            let dir = String(line[dirStart.upperBound..<dirEnd])
            guard dir.hasPrefix("/") else { continue }
            found[label] = dir
        }
        return found
    }

    private func script(services: Set<ServiceID>, settings: ServiceSettings) throws -> String {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: appKey),
            services: services,
            serviceSettings: settings
        )
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" }?.contents,
                             bundle.artifacts.map(\.fileName).joined(separator: ", "))
    }

    func testEveryBackupCapableServiceStatesItsDirectoryInTheShapeTheAgentReads() throws {
        let settings = ServiceSettings()
        let services: Set<ServiceID> = [.nextcloud, .immich, .forgejo, .dockerMailserver,
                                        .jellyfin, .vaultwarden, .wireguardVPN]
        let found = wrapperDirectories(in: try script(services: services, settings: settings))
        let context = ServiceContext(domain: "example.com", sshUser: "admin", settings: settings)

        for id in [ServiceID.nextcloud, .immich, .forgejo, .dockerMailserver, .jellyfin] {
            XCTAssertEqual(found[id.rawValue], context.backupDirectory(for: id),
                           "\(id.rawValue) must name its backup directory where the agent looks")
        }
        XCTAssertEqual(found[ServiceID.vpnPanel.rawValue],
                       context.backupDirectory(for: .vpnPanel))
        XCTAssertEqual(found[ServiceID.vaultwarden.rawValue],
                       context.backupDirectory(for: .vaultwarden))
    }

    func testTheDirectoryFollowsTheDeploymentsOwnBackupRoot() throws {
        let settings = ServiceSettings(backupRoot: "/srv/backups")
        let found = wrapperDirectories(in: try script(services: [.nextcloud], settings: settings))
        XCTAssertEqual(found["nextcloud"], "/srv/backups/nextcloud")
    }

    func testAServerWithNoBackupCapableServiceStatesNoDirectoriesAtAll() throws {
        let found = wrapperDirectories(in: try script(services: [], settings: ServiceSettings()))
        XCTAssertTrue(found.isEmpty, "\(found)")
    }
    func testTheCatalogsBackupCapableSetMatchesTheAgentsOwnList() {
        let agentsList: Set<String> = [
            "mailcow", "mailu", "docker-mailserver",
            "vaultwarden", "psono", "passbolt",
            "nextcloud", "seafile", "immich", "photoprism",
            "forgejo", "gitlab", "jellyfin",
            "minecraft-java", "minecraft-bedrock", "crafty-controller",
            "adguard-home", "pihole", "homepage", "authelia", "headscale",
            "vpn-panel",
            "open-webui", "litellm",
            "n8n",
            "anythingllm", "qdrant",
            "openclaw",
            "home-assistant", "mosquitto", "zigbee2mqtt"
        ]
        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        var fromCatalog: Set<String> = []
        for service in ServiceRegistry.all {
            guard let backup = service.actions(context).backup else { continue }
            switch backup {
            case .wrapperScript(let spec): fromCatalog.insert(spec.wrapperTarget)
            case .encryptedVolume: fromCatalog.insert(service.id.rawValue)
            }
        }
        XCTAssertEqual(fromCatalog, agentsList,
                       "the catalog and the agent disagree about which services have a backup — "
                       + "add the missing arm to Agent/gryonixnexusd/src/install/host/backup_ctl.rs "
                       + "and its id to BACKUP_CAPABLE_SERVICE_IDS")
    }

    func testTheCatalogsRestorableAndUpdatableSetsMatchTheAgentsOwnLists() {
        let agentsRestorable: Set<String> = [
            "mailcow", "mailu", "docker-mailserver",
            "vaultwarden", "psono", "passbolt",
            "nextcloud", "seafile", "immich", "photoprism",
            "forgejo", "gitlab", "jellyfin",
            "minecraft-java", "minecraft-bedrock", "crafty-controller",
            "adguard-home", "pihole", "headscale", "homepage", "authelia",
            "vpn-panel",
            "open-webui", "litellm",
            "n8n",
            "anythingllm", "qdrant", "openclaw",
            "home-assistant", "mosquitto", "zigbee2mqtt"
        ]
        let agentsUpdatable: Set<String> = [
            "mailu", "docker-mailserver", "vaultwarden", "psono", "passbolt",
            "nextcloud", "seafile", "immich", "photoprism", "forgejo", "jellyfin",
            "adguard-home", "pihole", "headscale", "tailscale-node", "cloudflared",
            "homepage", "authelia", "amnezia-wg", "shadowsocks", "xray-reality",
            "minecraft-java", "minecraft-bedrock", "crafty-controller",
            "open-webui", "ollama", "litellm",
            "n8n",
            "anythingllm", "qdrant",
            "searxng", "openclaw",
            "home-assistant", "mosquitto", "zigbee2mqtt"
        ]
        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        var restorable: Set<String> = []
        var updatable: Set<String> = []
        for service in ServiceRegistry.all {
            if service.actions(context).restore != nil { restorable.insert(service.id.rawValue) }
            let update = service.updateSpec(context)
            if update.flavour == .composePull, !update.images.isEmpty {
                updatable.insert(service.id.rawValue)
            }
        }
        XCTAssertEqual(restorable, agentsRestorable,
                       "the catalog and Agent/…/install/host/restore.rs's RESTORABLE_ORDER disagree")
        XCTAssertEqual(updatable, agentsUpdatable,
                       "the catalog and Agent/…/install/host/update_ctl.rs's "
                       + "UPDATE_CAPABLE_SERVICE_IDS disagree")
    }
}
