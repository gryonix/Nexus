import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf

/// What the demo agent remembers between calls
actor DemoAgentState {
    static let shared = DemoAgentState()

    private init() {}

    struct Memory {
        var passwordLoginOpen = false
        var keyOnlyUsers: Set<String> = []
        var lockedOutUsers: Set<String> = ["backup"]
        var bans: [Ban] = []
        var allowlist: [Allowed] = []
        var autoRulesEnabled = false
        var autoRuleCountries: [String] = []
        var dynamicDNSEnabled = false
        var dynamicDNSNames: [String] = []
        var autoLogoutMonths: Int32 = 0
        var devices: [Gryonixnexusd_V1_Device] = []
        var jobs: [Gryonixnexusd_V1_Job] = []
        var vault: [String: String] = [:]
        var models: [String] = ["llama3.2:3b", "qwen2.5:7b"]
        var modFiles: [String: [String]] = [:]
        /// Per VPN protocol id
        var vpnClients: [String: [VPNDevice]] = [:]
        var nextOctet: [String: Int] = [:]
        var vpnDefaultDNS = ["1.1.1.1"]
        var vpnDNSPriority = ["local", "1.1.1.1"]
        var meshUsers: [(id: String, name: String)] = []
        var meshNodes: [MeshMember] = []
        var meshNames: [(name: String, address: String)] = []
        var groupNames: [String: String] = [:]
        var removedGroups: Set<String> = []
        var stoppedGroups: Set<String> = []
    }

    /// One address the defence is holding
    struct Ban {
        var id: String
        var scope: String
        var value: String
        var reason: String
        var country: String
        var asName: String
        var source: String
        var expiresIn: String
        var events: UInt32
    }

    struct Allowed {
        var value: String
        var comment: String
    }

    struct VPNDevice {
        var id: String
        var name: String
        var detail: String
        var dns = ["1.1.1.1"]
    }

    struct MeshMember {
        var id: String
        var name: String
        var address: String
        var user: String
        var online: Bool
        var lastSeen: Date
    }

    private var memories: [UUID: Memory] = [:]

    /// Forgets everything
    func forgetEverything() { memories = [:] }

    func memory(_ machine: DemoAgentMachine) -> Memory {
        if let existing = memories[machine.id] { return existing }
        var seeded = Memory()
        seeded.devices = [Self.device(label: "iPhone", ago: 86_400 * 12),
                          Self.device(label: "MacBook Pro", ago: 86_400 * 40)]
        seeded.keyOnlyUsers = [machine.deployment.dashboardConfig.sshUser]
        seeded.bans = Self.seededBans
        seeded.allowlist = [Allowed(value: "203.0.113.9", comment: "office")]
        seeded.meshUsers = [(id: "1", name: "gryonixnexus"), (id: "2", name: "devices")]
        seeded.meshNodes = Self.seededMesh(machine)
        seeded.vpnClients = Self.seededVPN(machine)
        seeded.vault = Self.seededVault(machine)
        memories[machine.id] = seeded
        return seeded
    }

    func write(_ memory: Memory, for machine: DemoAgentMachine) {
        memories[machine.id] = memory
    }

    private static func device(label: String, ago: TimeInterval) -> Gryonixnexusd_V1_Device {
        var device = Gryonixnexusd_V1_Device()
        device.id = UUID().uuidString
        device.label = label
        device.publicKey = "ssh-ed25519 DEMO+\(label.replacingOccurrences(of: " ", with: ""))"
        device.scopes = ["read"]
        device.pairedAt = Int64(Date().addingTimeInterval(-ago).timeIntervalSince1970 * 1000)
        device.lastSeenAt = Int64(Date().addingTimeInterval(-3_600).timeIntervalSince1970 * 1000)
        return device
    }

    // MARK: - What a machine starts with

    static let seededBans = [
        Ban(id: "270036", scope: "Ip", value: "193.233.199.37",
            reason: "crowdsecurity/ssh-slow-bf", country: "RU", asName: "44812 IPHOST",
            source: "crowdsec", expiresIn: "3h6m42s", events: 11),
        Ban(id: "270041", scope: "Range", value: "198.51.100.0/24",
            reason: "gryonixnexus: added by hand", country: "", asName: "",
            source: "cscli", expiresIn: "22h14m", events: 1)
    ]

    static func seededMesh(_ machine: DemoAgentMachine) -> [MeshMember] {
        guard machine.deployment.services.contains(.headscale) else { return [] }
        let now = Date()
        return [
            MeshMember(id: "1", name: "gryonix-com", address: "100.64.0.1",
                       user: "gryonixnexus", online: true, lastSeen: now),
            MeshMember(id: "2", name: "iphone", address: "100.64.0.2",
                       user: "devices", online: true, lastSeen: now.addingTimeInterval(-180)),
            MeshMember(id: "3", name: "macbook-air", address: "100.64.0.3",
                       user: "devices", online: false, lastSeen: now.addingTimeInterval(-7_200))
        ]
    }

    /// The devices each protocol on this machine starts with
    static func seededVPN(_ machine: DemoAgentMachine) -> [String: [VPNDevice]] {
        var seeded: [String: [VPNDevice]] = [:]
        for id in machine.deployment.services where ServiceID.vpnProtocols.contains(id) {
            let names = Self.startingNames(machine.id, id)
            guard !names.isEmpty else { continue }
            seeded[id.rawValue] = names.enumerated().map { index, name in
                device(named: name, protocol: id, octet: index + 2)
            }
        }
        return seeded
    }

    private static func startingNames(_ deployment: UUID, _ id: ServiceID) -> [String] {
        switch (deployment, id) {
        case (DemoServer.id, .wireguardVPN): return ["iPhone", "MacBook Air", "iPad"]
        case (DemoServer.id, .amneziaWG): return ["iPhone abroad", "Travel laptop"]
        case (DemoServer.id, .xrayReality): return ["Work phone"]
        case (DemoServer.relayPairID, .wireguardVPN): return ["Phone", "Work laptop"]
        case (DemoServer.relayPairID, .shadowsocks): return ["Tablet"]
        case (DemoServer.relayPairID, .openVPN): return ["Old router", "Windows PC"]
        case (DemoServer.relayPairID, .xrayReality): return ["Travel phone"]
        default: return []
        }
    }

    static func device(named name: String, protocol id: ServiceID, octet: Int) -> VPNDevice {
        switch id {
        case .amneziaWG: return VPNDevice(id: "awg-\(octet)", name: name, detail: "10.10.0.\(octet)")
        case .openVPN: return VPNDevice(id: "ovpn-\(octet)", name: name, detail: "certificate")
        case .shadowsocks: return VPNDevice(id: "ss-\(octet)", name: name, detail: "Shadowsocks")
        case .xrayReality: return VPNDevice(id: "xray-\(octet)", name: name,
                                            detail: "VLESS · Reality")
        default: return VPNDevice(id: "wg-\(octet)", name: name, detail: "10.9.0.\(octet)")
        }
    }

    /// The passwords a demo installation would have written
    static func seededVault(_ machine: DemoAgentMachine) -> [String: String] {
        let domain = machine.deployment.domain
        let entries = machine.deployment.installedServices.prefix(4).map { service in
            entry(id: service.id.rawValue,
                  title: service.displayName,
                  website: "\(service.id.rawValue).\(domain)",
                  login: "admin@\(domain)")
        }
        return entries.reduce(into: [:]) { store, made in
            store[made.id] = (try? made.serializedData().base64EncodedString()) ?? ""
        }
    }

    private static func entry(id: String, title: String, website: String,
                              login: String) -> Gryonixnexusd_V1_VaultEntry {
        var made = Gryonixnexusd_V1_VaultEntry()
        made.id = id
        made.title = title
        made.website = website
        made.login = login
        made.password = "DEMO-NOT-A-PASSWORD"
        made.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        made.updatedBy = "the installation"
        return made
    }

    // MARK: - Dispatch

    func unary(path: String, request: Data, machine: DemoAgentMachine) async throws -> Data? {
        if let answer = try await control(path, request, machine) { return answer }
        if let answer = try await security(path, request, machine) { return answer }
        if let answer = try await maintenance(path, request, machine) { return answer }
        if let answer = try await services(path, request, machine) { return answer }
        return nil
    }

    func stream(path: String, request: Data,
                machine: DemoAgentMachine) async throws -> [DemoAgentStep] {
        if let steps = try await controlStream(path, request, machine) { return steps }
        if let steps = try await servicesStream(path, request, machine) { return steps }
        return []
    }

    // MARK: - Shared shapes

    /// Which services this machine still carries
    func present(_ machine: DemoAgentMachine) async -> [ServiceID] {
        let power = await DemoFleetState.shared.power(of: machine.id, containers: machine.containers)
        return machine.deployment.installedServices.map(\.id)
            .filter { !power.removed.contains($0.rawValue) }
    }

    /// Whether the machine says a service is running
    func isRunning(_ id: String, on machine: DemoAgentMachine) async -> Bool {
        let power = await DemoFleetState.shared.power(of: machine.id, containers: machine.containers)
        return !power.stopped.contains(id) && !power.removed.contains(id)
    }

    static func progressLines(_ subject: String, verb: String) -> [String] {
        ["==> \(verb) \(subject)",
         "Pulling images…",
         "Creating containers…",
         "Waiting for the health check…",
         "\(subject): done"]
    }
}
