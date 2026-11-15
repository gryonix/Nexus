import AgentClient
import Foundation
import SwiftProtobuf

/// Modules, MCP, home-only sites, networks, audio and moves
extension DemoAgentState {
    func gaps(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        if let answer = try exposure(path, request, machine) { return answer }
        if let answer = try networks(path, request, machine) { return answer }
        if let answer = try audio(path, request) { return answer }
        return try leftovers(path, request, machine)
    }

    private func exposure(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        var stored = memory(machine)
        defer { write(stored, for: machine) }
        switch path {
        case "/gryonixnexusd.v1.AppModules/GetAppModules":
            return Gryonixnexusd_V1_AppModuleSet.with { $0.on = stored.appModules }.demoPayload
        case "/gryonixnexusd.v1.AppModules/SetAppModules":
            stored.appModules = try Gryonixnexusd_V1_AppModuleSet(serializedBytes: request).on
            return Gryonixnexusd_V1_AppModuleSet.with { $0.on = stored.appModules }.demoPayload
        case "/gryonixnexusd.v1.ServiceNames/GetServiceNames":
            return Gryonixnexusd_V1_ServiceNameSet.with { $0.names = stored.serviceNames }.demoPayload
        case "/gryonixnexusd.v1.ServiceNames/SetServiceName":
            let asked = try Gryonixnexusd_V1_SetServiceNameRequest(serializedBytes: request)
            stored.serviceNames[asked.serviceID] = asked.name.isEmpty ? nil : asked.name
            return Gryonixnexusd_V1_ServiceNameSet.with { $0.names = stored.serviceNames }.demoPayload
        case "/gryonixnexusd.v1.McpAccess/SetMcpAccess":
            stored.mcpOn = try Gryonixnexusd_V1_SetMcpAccessRequest(serializedBytes: request).enabled
            return Self.mcp(stored.mcpOn).demoPayload
        case "/gryonixnexusd.v1.McpAccess/GetMcpAccess":
            return Self.mcp(stored.mcpOn).demoPayload
        case "/gryonixnexusd.v1.Exposure/SetLocalAlias":
            let asked = try Gryonixnexusd_V1_SetLocalAliasRequest(serializedBytes: request)
            stored.localAliases.removeAll { $0 == asked.host }
            if asked.on { stored.localAliases.append(asked.host) }
            return Self.aliases(stored.localAliases).demoPayload
        case "/gryonixnexusd.v1.Exposure/GetLocalAliases":
            return Self.aliases(stored.localAliases).demoPayload
        case "/gryonixnexusd.v1.Exposure/SetHomeOnlyPorts":
            stored.homeOnlyPorts = try Gryonixnexusd_V1_SetHomeOnlyPortsRequest(serializedBytes: request).ports
            return Gryonixnexusd_V1_SetHomeOnlyPortsResponse.with { $0.ports = stored.homeOnlyPorts }.demoPayload
        case "/gryonixnexusd.v1.Exposure/ProbePublicPorts":
            let asked = try Gryonixnexusd_V1_ProbePublicPortsRequest(serializedBytes: request)
            let closed = Set(stored.homeOnlyPorts.map(\.port))
            return Gryonixnexusd_V1_ProbePublicPortsResponse.with { answer in
                answer.ports = asked.ports.map { port in .with { $0.port = port; $0.open = !closed.contains(port) } }
            }.demoPayload
        case "/gryonixnexusd.v1.Exposure/GetLocalRootCA":
            return Gryonixnexusd_V1_GetLocalRootCAResponse.with { $0.pem = Self.demoRootPEM }.demoPayload
        default:
            return nil
        }
    }

    private static func mcp(_ on: Bool) -> Gryonixnexusd_V1_McpAccessState {
        .with {
            $0.enabled = on
            $0.users = on ? ["server-user"] : []
            $0.command = on ? "gryonixnexusd mcp" : ""
        }
    }

    private static func aliases(_ hosts: [String]) -> Gryonixnexusd_V1_LocalAliasesState {
        .with { state in
            state.aliases = hosts.map { host in
                .with { $0.host = host; $0.alias = "\(host.split(separator: ".").first ?? "site").local" }
            }
        }
    }

    private static let demoRootPEM = "-----BEGIN CERTIFICATE-----\nZGVtbw==\n-----END CERTIFICATE-----\n"
}

/// Docker networks of a demo machine
extension DemoAgentState {
    private func networks(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Containers/ListNetworks":
            return networkList(machine).demoPayload
        case "/gryonixnexusd.v1.Containers/RemoveNetwork":
            let asked = try Gryonixnexusd_V1_RemoveNetworkRequest(serializedBytes: request)
            let network = networkList(machine).networks.first { $0.name == asked.name }
            let removable = network.map { !$0.builtin && !$0.inUse } ?? false
            if removable {
                var stored = memory(machine)
                stored.removedNetworks.insert(asked.name)
                write(stored, for: machine)
            }
            return Gryonixnexusd_V1_DockerRemovalResult.with {
                $0.removed = removable
                $0.message = removable ? "" : "network \(asked.name) is in use"
            }.demoPayload
        default:
            return nil
        }
    }

    private func networkList(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_NetworkInventory {
        let removed = memory(machine).removedNetworks
        var all = [Self.network("bridge", builtin: true, containers: 0),
                   Self.network("host", builtin: true, containers: 0),
                   Self.network("none", builtin: true, containers: 0),
                   Self.network("demo_unused", builtin: false, containers: 0)]
        all += machine.containers.prefix(6).enumerated().map { index, id in
            var made = Self.network("\(id)_default", builtin: false, containers: 2)
            made.managed = true
            made.subnet = "172.\(20 + index).0.0/16"
            return made
        }
        return .with { $0.networks = all.filter { !removed.contains($0.name) } }
    }

    private static func network(_ name: String, builtin: Bool, containers: UInt32) -> Gryonixnexusd_V1_DockerNetwork {
        .with {
            $0.id = String(name.utf8.map { String(format: "%02x", $0) }.joined().prefix(12))
            $0.name = name
            $0.driver = name == "host" || name == "none" ? name : "bridge"
            $0.scope = "local"
            $0.containers = containers
            $0.inUse = containers > 0
            $0.builtin = builtin
        }
    }
}

extension DemoAgentState {
    private func audio(_ path: String, _ request: Data) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Audio/ListAudioOutputs":
            return Gryonixnexusd_V1_ListAudioOutputsResponse.with {
                $0.outputs = [.with { $0.device = "hw:CARD=Headphones,DEV=0"; $0.title = "bcm2835 Headphones"
                                      $0.mixers = ["PCM"] }]
            }.demoPayload
        case "/gryonixnexusd.v1.Audio/OdioCall":
            let asked = try Gryonixnexusd_V1_OdioCallRequest(serializedBytes: request)
            return Gryonixnexusd_V1_OdioCallResponse.with {
                $0.status = 200
                $0.body = asked.method == "GET" || asked.path == "/gryonixnexus/settings" ? Self.odioBody(asked.path) : "{}"
            }.demoPayload
        default:
            return nil
        }
    }

    private static func odioBody(_ path: String) -> String {
        switch path {
        case "/audio/server": return #"{"volume":0.42,"muted":false}"#
        case "/audio/outputs":
            return #"[{"name":"alsa_output.headphones","description":"Headphones","volume":0.42,"default":true}]"#
        case "/players":
            return #"[{"bus_name":"org.mpris.MediaPlayer2.mpd","identity":"Music Player Daemon","playback_status":"Playing","metadata":{"xesam:title":"Demo track","xesam:artist":"gryonix"},"capabilities":{"can_go_next":true,"can_go_previous":true}}]"#
        case "/services":
            return #"[{"name":"mpd.service","scope":"user","description":"Music Player Daemon","running":true},{"name":"shairport-sync.service","scope":"user","description":"AirPlay","running":true}]"#
        case "/bluetooth": return #"{"powered":true,"pairing_active":false}"#
        case "/gryonixnexus/settings":
            return #"{"spotify.name":"Home server","spotify.bitrate":"320","spotify.normalise":"false","spotify.volume":"100","airplay.name":"Home server"}"#
        default: return "{}"
        }
    }
}

/// Certificates, the agent switch, restore copies, moves and storage
extension DemoAgentState {
    private func leftovers(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        if let answer = try restoreOrMove(path, request, machine) { return answer }
        switch path {
        case "/gryonixnexusd.v1.Install/RefreshCertificates":
            return Gryonixnexusd_V1_RefreshCertificatesResponse.with { $0.reloaded = true }.demoPayload
        case "/gryonixnexusd.v1.AgentUpdate/SetAgentAutoUpdate":
            var stored = memory(machine)
            stored.agentAutoUpdate = try Gryonixnexusd_V1_SetAgentAutoUpdateRequest(serializedBytes: request).enabled
            write(stored, for: machine)
            return Gryonixnexusd_V1_AgentUpdateStatus.with {
                $0.installedVersion = DemoAgentOffer.installedVersion
                $0.autoUpdate = stored.agentAutoUpdate
            }.demoPayload
        case "/gryonixnexusd.v1.AgentUpdate/RemoveAgent":
            return Gryonixnexusd_V1_RemoveAgentResponse.with { $0.scheduled = true }.demoPayload
        case "/gryonixnexusd.v1.Storage/RunStorageTask":
            return Gryonixnexusd_V1_StorageTaskResult.with { $0.exitCode = 0; $0.output = "done (demo)" }.demoPayload
        case "/gryonixnexusd.v1.Pairing/CreateTransfer":
            return Gryonixnexusd_V1_CreateTransferResponse.with {
                $0.transferID = UUID().uuidString
                $0.privateKeySeed = Data(repeating: 7, count: 32)
                $0.expiresAt = Int64(Date().addingTimeInterval(600).timeIntervalSince1970 * 1000)
            }.demoPayload
        default:
            return nil
        }
    }

    private func restoreOrMove(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Restore/ListPreRestoreCopies":
            let asked = try Gryonixnexusd_V1_ListPreRestoreCopiesRequest(serializedBytes: request)
            return copies(asked.serviceID, machine).demoPayload
        case "/gryonixnexusd.v1.Restore/DeletePreRestoreCopy":
            let asked = try Gryonixnexusd_V1_DeletePreRestoreCopyRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.preRestoreCopies.append(asked.path)
            write(stored, for: machine)
            return copies("", machine).demoPayload
        case "/gryonixnexusd.v1.Move/SetServiceUpstream":
            let asked = try Gryonixnexusd_V1_SetServiceUpstreamRequest(serializedBytes: request)
            return Gryonixnexusd_V1_ServiceUpstreamState.with {
                $0.current = asked.remoteAddress.isEmpty ? "local" : "remote"
                $0.remoteAddress = asked.remoteAddress
                $0.changed = !asked.dryRun
            }.demoPayload
        case "/gryonixnexusd.v1.Move/ProbeServiceUpstream":
            return Gryonixnexusd_V1_ServiceUpstreamProbe.with { $0.answered = true; $0.status = 200 }.demoPayload
        case "/gryonixnexusd.v1.Move/PrepareMoveSend":
            return Gryonixnexusd_V1_PrepareMoveSendResponse.with { $0.publicKey = "ssh-ed25519 AAAADEMO demo" }.demoPayload
        case "/gryonixnexusd.v1.Move/PrepareMoveReceive":
            return Gryonixnexusd_V1_PrepareMoveReceiveResponse.with {
                $0.authorizedKeyLine = "ssh-ed25519 AAAADEMO demo"
                $0.freeBytes = 41_000_000_000
            }.demoPayload
        case "/gryonixnexusd.v1.Move/DiscardMoveTransfer":
            return Gryonixnexusd_V1_DiscardMoveTransferResponse().demoPayload
        default:
            return nil
        }
    }

    /// One copy per service, until deleted
    private func copies(_ serviceID: String, _ machine: DemoAgentMachine) -> Gryonixnexusd_V1_PreRestoreCopyList {
        let deleted = Set(memory(machine).preRestoreCopies)
        let services = serviceID.isEmpty ? machine.containers : [serviceID]
        return .with { list in
            list.copies = services.map { id in
                .with {
                    $0.serviceID = id
                    $0.path = "/opt/\(id).before-restore"
                    $0.sizeBytes = 182_000_000
                    $0.sizeKnown = true
                    $0.movedAsideUnix = Int64(Date().addingTimeInterval(-86_400 * 3).timeIntervalSince1970)
                }
            }.filter { !deleted.contains($0.path) }
        }
    }
}
