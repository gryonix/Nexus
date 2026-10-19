import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf

extension DemoAgentState {
    /// Mail, DKIM, mods, models, mesh, VPN clients and containers
    func services(_ path: String, _ request: Data,
                  _ machine: DemoAgentMachine) async throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Mail/ListMailboxes":
            return await mailboxes(machine).demoPayload
        case "/gryonixnexusd.v1.Mail/CreateMailbox":
            let asked = try Gryonixnexusd_V1_CreateMailboxRequest(serializedBytes: request)
            await DemoFleetState.shared.addMailbox(asked.address, deployment: machine.id,
                                                   containers: machine.containers)
            return await mailboxes(machine).demoPayload
        case "/gryonixnexusd.v1.Mail/DeleteMailbox":
            let asked = try Gryonixnexusd_V1_DeleteMailboxRequest(serializedBytes: request)
            await DemoFleetState.shared.removeMailbox(asked.address, deployment: machine.id,
                                                      containers: machine.containers)
            return await mailboxes(machine).demoPayload
        case "/gryonixnexusd.v1.Mail/SetMailboxPassword":
            return await mailboxes(machine).demoPayload
        case "/gryonixnexusd.v1.Dkim/GetDkimRecords":
            return Self.dkim(machine).demoPayload
        case "/gryonixnexusd.v1.Install/ProvisionHost":
            var answer = Gryonixnexusd_V1_ProvisionHostResponse()
            answer.written = ["/etc/caddy/Caddyfile", "/opt/gryonixnexus/compose"]
            answer.controlUser = machine.deployment.dashboardConfig.sshUser
            return answer.demoPayload
        case "/gryonixnexusd.v1.Install/StartInstallPlan":
            let asked = try Gryonixnexusd_V1_StartInstallPlanRequest(serializedBytes: request)
            let ids = asked.services.map(\.serviceID)
            for id in ids {
                await DemoFleetState.shared.install(service: id, deployment: machine.id, containers: machine.containers)
            }
            return try await DemoInstallPlans.shared.start(ids, purpose: asked.purpose).demoPayload
        case "/gryonixnexusd.v1.Install/GetInstallPlan":
            let asked = try Gryonixnexusd_V1_GetInstallPlanRequest(serializedBytes: request)
            return await DemoInstallPlans.shared.get(asked.planID).demoPayload
        default:
            return try modsOrModels(path, request, machine)
        }
    }

    private func mailboxes(_ machine: DemoAgentMachine) async -> Gryonixnexusd_V1_MailboxList {
        let stored = await DemoFleetState.shared.mailboxes(of: machine.id,
                                                            containers: machine.containers)
        var list = Gryonixnexusd_V1_MailboxList()
        list.mailboxes = stored.map { address in
            var box = Gryonixnexusd_V1_Mailbox()
            box.address = address
            box.detail = "6.0K used"
            box.manageable = true
            return box
        }
        return list
    }

    private static func dkim(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_DkimRecordList {
        var record = Gryonixnexusd_V1_DkimRecord()
        record.name = "dkim._domainkey.\(machine.deployment.domain)"
        record.value = "v=DKIM1;k=rsa;p=" + String(repeating: "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A", count: 6)
        var list = Gryonixnexusd_V1_DkimRecordList()
        list.records = [record]
        return list
    }

    // MARK: - Mods and models

    private func modsOrModels(_ path: String, _ request: Data,
                              _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Mods/SearchMods":
            return Self.modSearch().demoPayload
        case "/gryonixnexusd.v1.Mods/ModVersions":
            return Self.modVersions().demoPayload
        case "/gryonixnexusd.v1.Mods/ListModFiles",
             "/gryonixnexusd.v1.Mods/UploadModFile",
             "/gryonixnexusd.v1.Mods/DeleteModFile":
            return try modFiles(path, request, machine).demoPayload
        case "/gryonixnexusd.v1.Vaultwarden/GetVaultwardenTwoFactor":
            var answer = Gryonixnexusd_V1_VaultwardenTwoFactor()
            answer.readable = true
            answer.users = 3
            answer.usersWithoutTwoFactor = 1
            return answer.demoPayload
        case "/gryonixnexusd.v1.Models/ListModels":
            return models(machine).demoPayload
        case "/gryonixnexusd.v1.Models/DeleteModel":
            let asked = try Gryonixnexusd_V1_DeleteModelRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.models.removeAll { $0 == asked.name }
            write(stored, for: machine)
            return models(machine).demoPayload
        default:
            return try meshOrVPN(path, request, machine)
        }
    }

    private func modFiles(_ path: String, _ request: Data,
                          _ machine: DemoAgentMachine) throws -> Gryonixnexusd_V1_ModFileList {
        var stored = memory(machine)
        if path.hasSuffix("UploadModFile") {
            let asked = try Gryonixnexusd_V1_UploadModFileRequest(serializedBytes: request)
            stored.modFiles[asked.serviceID, default: []].append(asked.name)
        }
        if path.hasSuffix("DeleteModFile") {
            let asked = try Gryonixnexusd_V1_DeleteModFileRequest(serializedBytes: request)
            stored.modFiles[asked.serviceID] = (stored.modFiles[asked.serviceID] ?? [])
                .filter { $0 != asked.name }
        }
        write(stored, for: machine)
        let asked = try? Gryonixnexusd_V1_ListModFilesRequest(serializedBytes: request)
        var list = Gryonixnexusd_V1_ModFileList()
        list.diskFreeBytes = 41_000_000_000
        list.files = (stored.modFiles[asked?.serviceID ?? ""] ?? []).map { name in
            var file = Gryonixnexusd_V1_ModFile()
            file.name = name
            file.slot = .mods
            file.sizeBytes = 812_544
            file.modifiedUnix = Int64(Date().timeIntervalSince1970)
            return file
        }
        return list
    }

    private static func modSearch() -> Gryonixnexusd_V1_ModSearchResult {
        var found = Gryonixnexusd_V1_ModSearchResult()
        found.projects = [project(slug: "fabric-api", title: "Fabric API",
                                  summary: "The core library every Fabric mod builds on"),
                          project(slug: "lithium", title: "Lithium",
                                  summary: "Server-side optimisation, no behaviour changes")]
        found.total = UInt32(found.projects.count)
        return found
    }

    private static func project(slug: String, title: String,
                                summary: String) -> Gryonixnexusd_V1_ModProject {
        var project = Gryonixnexusd_V1_ModProject()
        project.slug = slug
        project.title = title
        project.description_p = summary
        project.projectID = slug
        project.projectType = "mod"
        project.author = "gryonixNexus demo"
        project.downloads = 9_400_000
        return project
    }

    private static func modVersions() -> Gryonixnexusd_V1_ModVersionList {
        var version = Gryonixnexusd_V1_ModVersion()
        version.versionID = "demo-1"
        version.versionNumber = "0.100.1"
        version.name = "Fabric API 0.100.1"
        version.versionType = "release"
        version.gameVersions = ["1.21"]
        version.loaders = ["fabric"]
        var list = Gryonixnexusd_V1_ModVersionList()
        list.versions = [version]
        return list
    }

    private func models(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_ModelList {
        var list = Gryonixnexusd_V1_ModelList()
        list.enginePresent = true
        list.path = "/var/lib/ollama"
        list.diskFreeBytes = 41_000_000_000
        list.diskTotalBytes = 120_000_000_000
        list.models = memory(machine).models.map { name in
            var model = Gryonixnexusd_V1_Model()
            model.name = name
            model.sizeBytes = 2_400_000_000
            return model
        }
        return list
    }

    // MARK: - Mesh and VPN clients

    private func meshOrVPN(_ path: String, _ request: Data,
                           _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Mesh/ListMeshUsers":
            return meshUsers(machine).demoPayload
        case "/gryonixnexusd.v1.Mesh/CreateMeshUser":
            let asked = try Gryonixnexusd_V1_CreateMeshUserRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.meshUsers.append((id: "\(stored.meshUsers.count + 1)", name: asked.name))
            write(stored, for: machine)
            return meshUsers(machine).demoPayload
        case "/gryonixnexusd.v1.Mesh/CreateMeshAuthKey":
            let asked = try Gryonixnexusd_V1_CreateMeshAuthKeyRequest(serializedBytes: request)
            var key = Gryonixnexusd_V1_MeshAuthKey()
            key.key = "demo-server-placeholder-not-a-key"
            key.reusable = asked.reusable
            key.expiresAt = Int64(Date().addingTimeInterval(Double(asked.expirationHours) * 3_600)
                .timeIntervalSince1970 * 1000)
            return key.demoPayload
        case "/gryonixnexusd.v1.Mesh/ListMeshNodes":
            return meshNodes(machine).demoPayload
        case "/gryonixnexusd.v1.Mesh/DeleteMeshNode":
            let asked = try Gryonixnexusd_V1_DeleteMeshNodeRequest(serializedBytes: request)
            var stored = memory(machine)
            if asked.nodeID != "1" { stored.meshNodes.removeAll { $0.id == asked.nodeID } }
            write(stored, for: machine)
            return meshNodes(machine).demoPayload
        case "/gryonixnexusd.v1.Mesh/PublishMeshNames":
            let asked = try Gryonixnexusd_V1_PublishMeshNamesRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.meshNames = asked.names.enumerated().map { index, name in
                (name: name, address: "100.64.0.\(index + 1)")
            }
            write(stored, for: machine)
            var list = Gryonixnexusd_V1_MeshNameList()
            list.records = stored.meshNames.map { published in
                var record = Gryonixnexusd_V1_MeshName()
                record.name = published.name
                record.address = published.address
                return record
            }
            return list.demoPayload
        default:
            return try vpn(path, request, machine)
        }
    }

    private func meshUsers(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_MeshUserList {
        var list = Gryonixnexusd_V1_MeshUserList()
        list.users = memory(machine).meshUsers.map { stored in
            var user = Gryonixnexusd_V1_MeshUser()
            user.id = stored.id
            user.name = stored.name
            return user
        }
        return list
    }

    private func meshNodes(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_MeshNodeList {
        var list = Gryonixnexusd_V1_MeshNodeList()
        list.nodes = memory(machine).meshNodes.map { stored in
            var node = Gryonixnexusd_V1_MeshNode()
            node.id = stored.id
            node.name = stored.name
            node.addresses = [stored.address]
            node.user = stored.user
            node.online = stored.online
            node.lastSeen = Int64(stored.lastSeen.timeIntervalSince1970 * 1000)
            return node
        }
        return list
    }

    private func vpn(_ path: String, _ request: Data,
                     _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Vpn/ListVpnClients":
            let asked = try Gryonixnexusd_V1_ListVpnClientsRequest(serializedBytes: request)
            return clients(of: asked.protocol, machine).demoPayload
        case "/gryonixnexusd.v1.Vpn/AddVpnClient":
            let asked = try Gryonixnexusd_V1_AddVpnClientRequest(serializedBytes: request)
            addClient(named: asked.name, protocol: asked.protocol, dns: asked.dns, machine)
            return clients(of: asked.protocol, machine).demoPayload
        case "/gryonixnexusd.v1.Vpn/SetVpnClientDns":
            let asked = try Gryonixnexusd_V1_SetVpnClientDnsRequest(serializedBytes: request)
            var stored = memory(machine)
            if let index = stored.vpnClients[asked.protocol]?.firstIndex(where: { $0.id == asked.clientID }) {
                stored.vpnClients[asked.protocol]?[index].dns = asked.dns
            }
            write(stored, for: machine)
            return clients(of: asked.protocol, machine).demoPayload
        case "/gryonixnexusd.v1.Vpn/GetVpnDns":
            return vpnDNS(machine).demoPayload
        case "/gryonixnexusd.v1.Vpn/SetVpnDns":
            let asked = try Gryonixnexusd_V1_VpnDns(serializedBytes: request)
            var stored = memory(machine)
            stored.vpnDefaultDNS = asked.dns
            write(stored, for: machine)
            return vpnDNS(machine).demoPayload
        case "/gryonixnexusd.v1.Vpn/GetVpnDnsPriority", "/gryonixnexusd.v1.Vpn/SetVpnDnsPriority",
             "/gryonixnexusd.v1.Vpn/ExportVpnState", "/gryonixnexusd.v1.Vpn/ImportVpnState":
            return try vpnMove(path, request, machine)
        case "/gryonixnexusd.v1.Vpn/DeleteVpnClient":
            let asked = try Gryonixnexusd_V1_DeleteVpnClientRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.vpnClients[asked.protocol]?.removeAll { $0.id == asked.clientID }
            write(stored, for: machine)
            return clients(of: asked.protocol, machine).demoPayload
        case "/gryonixnexusd.v1.Vpn/GetVpnClientConfig":
            let asked = try Gryonixnexusd_V1_GetVpnClientConfigRequest(serializedBytes: request)
            return DemoVPNConfig.make(protocol: asked.protocol, clientID: asked.clientID)
                .demoPayload
        default:
            return try containers(path, request, machine)
        }
    }

    /// The DNS order and the VPN's packed folders
    private func vpnMove(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        var stored = memory(machine)
        switch path {
        case "/gryonixnexusd.v1.Vpn/SetVpnDnsPriority":
            stored.vpnDNSPriority = try Gryonixnexusd_V1_VpnDnsPriority(serializedBytes: request).resolvers
            write(stored, for: machine)
            fallthrough
        case "/gryonixnexusd.v1.Vpn/GetVpnDnsPriority":
            var priority = Gryonixnexusd_V1_VpnDnsPriority()
            priority.resolvers = stored.vpnDNSPriority
            priority.localAvailable = true
            priority.reachable = stored.vpnDNSPriority.map { _ in true }
            return priority.demoPayload
        case "/gryonixnexusd.v1.Vpn/ExportVpnState":
            var state = Gryonixnexusd_V1_VpnState()
            state.directories = try Gryonixnexusd_V1_ExportVpnStateRequest(serializedBytes: request).directories
            state.archive = Data("demo".utf8)
            return state.demoPayload
        default:
            var answer = Gryonixnexusd_V1_ImportVpnStateResponse()
            answer.directories = try Gryonixnexusd_V1_ImportVpnStateRequest(serializedBytes: request).directories
            return answer.demoPayload
        }
    }

    private func clients(of id: String,
                         _ machine: DemoAgentMachine) -> Gryonixnexusd_V1_VpnClientList {
        var list = Gryonixnexusd_V1_VpnClientList()
        list.clients = (memory(machine).vpnClients[id] ?? []).map { stored in
            var client = Gryonixnexusd_V1_VpnClient()
            client.id = stored.id
            client.name = stored.name
            client.detail = stored.detail
            client.dns = stored.dns
            return client
        }
        return list
    }

    private func addClient(named name: String, protocol id: String, dns: [String], _ machine: DemoAgentMachine) {
        var stored = memory(machine)
        let octet = stored.nextOctet[id] ?? ((stored.vpnClients[id]?.count ?? 0) + 2)
        stored.nextOctet[id] = octet + 1
        var made = DemoAgentState.device(named: name, protocol: ServiceID(rawValue: id),
                                         octet: octet)
        made.dns = dns.isEmpty ? stored.vpnDefaultDNS : dns
        stored.vpnClients[id, default: []].append(made)
        write(stored, for: machine)
    }

    // MARK: - Containers

    private func containers(_ path: String, _ request: Data,
                            _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Containers/ListContainers":
            return inventory(machine).demoPayload
        case "/gryonixnexusd.v1.Containers/SetContainerGroupName":
            let asked = try Gryonixnexusd_V1_SetContainerGroupNameRequest(serializedBytes: request)
            var stored = memory(machine)
            let wanted = asked.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            stored.groupNames[asked.key] = wanted.isEmpty ? nil : wanted
            write(stored, for: machine)
            return inventory(machine).demoPayload
        case "/gryonixnexusd.v1.Containers/InspectContainer":
            let asked = try Gryonixnexusd_V1_InspectContainerRequest(serializedBytes: request)
            return Self.detail(of: asked.name).demoPayload
        case "/gryonixnexusd.v1.Containers/PreviewContainerGroupRemoval":
            let asked = try Gryonixnexusd_V1_PreviewContainerGroupRemovalRequest(
                serializedBytes: request)
            var preview = Gryonixnexusd_V1_ContainerRemovalPreview()
            preview.key = asked.key
            preview.containers = ["\(asked.key)-app-1"]
            preview.volumes = ["\(asked.key)_data"]
            preview.paths = ["/opt/\(asked.key)"]
            return preview.demoPayload
        case "/gryonixnexusd.v1.Containers/GetContainerBackupPlan",
             "/gryonixnexusd.v1.Containers/SetContainerBackupPlan":
            return Gryonixnexusd_V1_ContainerBackupPlan().demoPayload
        case "/gryonixnexusd.v1.Containers/GetContainerBackupSchedule",
             "/gryonixnexusd.v1.Containers/SetContainerBackupSchedule":
            return Gryonixnexusd_V1_ContainerBackupSchedule().demoPayload
        case "/gryonixnexusd.v1.Containers/ListContainerGroupBackups":
            return Gryonixnexusd_V1_ContainerBackupList().demoPayload
        default:
            return nil
        }
    }

    /// The default DNS, and the demo's own resolver
    func vpnDNS(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_VpnDns {
        var answer = Gryonixnexusd_V1_VpnDns()
        answer.dns = memory(machine).vpnDefaultDNS
        answer.localAddress = "10.53.0.53"
        let installed = Set(machine.deployment.installedServices.map(\.id))
        answer.localServices = [ServiceID.adguardHome, .pihole].filter(installed.contains).map(\.rawValue)
        return answer
    }

    func inventory(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_ContainerInventory {
        let stored = memory(machine)
        var groups = machine.deployment.installedServices
            .filter { !stored.removedGroups.contains($0.id.rawValue) }
            .map { service -> Gryonixnexusd_V1_ContainerGroup in
                Self.group(key: service.id.rawValue, name: service.displayName,
                           serviceID: service.id.rawValue, memory: stored)
            }
        groups.append(Self.group(key: "uptime-kuma", name: "Uptime Kuma",
                                 serviceID: "", memory: stored))
        var inventory = Gryonixnexusd_V1_ContainerInventory()
        inventory.groups = groups
        return inventory
    }

    private static func group(key: String, name: String, serviceID: String,
                              memory: Memory) -> Gryonixnexusd_V1_ContainerGroup {
        let isRunning = !memory.stoppedGroups.contains(key)
        var group = Gryonixnexusd_V1_ContainerGroup()
        group.key = key
        group.kind = serviceID.isEmpty ? .standalone : .composeProject
        group.derivedName = name
        group.displayName = memory.groupNames[key] ?? name
        group.renamed = memory.groupNames[key] != nil
        group.serviceID = serviceID
        group.status = isRunning ? .running : .stopped
        var container = Gryonixnexusd_V1_Container()
        container.name = serviceID.isEmpty ? key : "\(key)-app-1"
        container.image = "\(key):latest"
        container.state = isRunning ? "running" : "exited"
        container.health = isRunning ? "healthy" : ""
        container.ports = isRunning ? "127.0.0.1:8080->80/tcp" : ""
        group.containers = [container]
        group.configFiles = serviceID.isEmpty ? [] : ["/opt/\(key)/docker-compose.yml"]
        return group
    }

    private static func detail(of name: String) -> Gryonixnexusd_V1_ContainerDetail {
        var container = Gryonixnexusd_V1_Container()
        container.name = name
        container.image = "\(name):latest"
        container.state = "running"
        container.health = "healthy"
        var detail = Gryonixnexusd_V1_ContainerDetail()
        detail.container = container
        detail.createdAt = "2026-08-16T21:04:11Z"
        detail.restartPolicy = "unless-stopped"
        detail.composeProject = name
        detail.composeService = "app"
        detail.env = [Self.env("TZ", "Europe/Berlin", sensitive: false),
                      Self.env("DB_PASSWORD", "••••••••", sensitive: true)]
        var mount = Gryonixnexusd_V1_ContainerMount()
        mount.source = "/opt/\(name)/data"
        mount.destination = "/data"
        mount.mode = "rw"
        mount.kind = "bind"
        detail.mounts = [mount]
        return detail
    }

    private static func env(_ key: String, _ value: String,
                            sensitive: Bool) -> Gryonixnexusd_V1_ContainerEnvVar {
        var variable = Gryonixnexusd_V1_ContainerEnvVar()
        variable.key = key
        variable.value = value
        variable.sensitive = sensitive
        return variable
    }
}
