import Foundation
import ServerControl
import ServerControlSSH

@available(macOS 15.0, *)
enum TerminalEndpointBuilder {
    enum Failure: LocalizedError {
        case notConfigured
        case unknownMachine
        case noLocalAddress

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return UIL10n.string("specify the server address and SSH user in the server settings")
            case .noLocalAddress:
                return UIL10n.string("specify the address on the network in the server settings")
            case .unknownMachine:
                return UIL10n.string("this deployment has no address for that machine")
            }
        }
    }

    /// Where to dial, in order, and how keys are kept
    struct Target {
        var routes: [TerminalEndpoint]
        var pinTargets: [String: SSHHostID]
        var bastionPins: [String: String] = [:]
        /// Remembers the route that worked, per machine
        var memoryKey: String

        var endpoint: TerminalEndpoint { routes[0] }

        /// Stores a key first seen on any of the routes
        func pinner(deploymentID: UUID) -> @Sendable (String, String) -> Void {
            let pins = HostKeyPinStore(deploymentID: deploymentID)
            let hosts = pinTargets
            let bastions = bastionPins
            return { host, key in
                if let id = hosts[host] {
                    pins.store(key, for: id)
                } else if let endpoint = bastions[host] {
                    pins.store(key, forBastion: endpoint)
                }
            }
        }
    }

    /// Short, so a missing network costs seconds
    static let localTimeout = Duration.seconds(4)
    static let publicTimeout = Duration.seconds(20)

    static func target(for deployment: Deployment, nodeID: UUID?) throws -> Target {
        let config = deployment.dashboardConfig
        guard config.isConnectable else { throw Failure.notConfigured }
        let pins = HostKeyPinStore(deploymentID: deployment.id)
        let access = ServerAccessStore.options(for: deployment.id)
        let proxy = DashboardSessionFactory.proxy(for: access)
        var bastionPins: [String: String] = [:]

        let entryNode = deployment.nodes.first
        guard let nodeID, nodeID != entryNode?.id else {
            let fleet = storedFleet()
            let chosen = storedVia(of: deployment.id).map {
                chosenRoutes(to: config.vpsHost, port: config.sshPort, pinned: pins.pin(for: .vps), via: $0, fleet: fleet)
            }
            let detours = chosen ?? homeDetours(to: config.vpsHost, port: config.sshPort,
                                                pinned: pins.pin(for: .vps), from: deployment.id, fleet: fleet)
            var routes = [TerminalEndpoint(host: config.vpsHost, port: config.sshPort,
                                           pinnedHostKey: pins.pin(for: .vps),
                                           parent: hop(access.bastion, deployment, &bastionPins),
                                           kind: .direct,
                                           connectTimeout: detours.isEmpty ? publicTimeout : localTimeout,
                                           proxy: proxy)]
            var pinTargets: [String: SSHHostID] = [config.vpsHost: .vps]
            for detour in detours {
                routes.append(detour)
                pinTargets[detour.host] = .vps
            }
            if let fallback = access.fallback, fallback.isUsable {
                let address = fallback.endpoint(primary: deployment.entry)
                routes.append(TerminalEndpoint(host: address.host, port: address.port,
                                               pinnedHostKey: pins.pin(for: .vps),
                                               parent: hop(fallback.bastion, deployment, &bastionPins),
                                               kind: .fallbackAddress, connectTimeout: publicTimeout,
                                               proxy: proxy))
                pinTargets[address.host] = .vps
            }
            if chosen?.isEmpty == false { routes.append(routes.removeFirst()) }
            return Target(routes: chosen == nil ? ordered(routes, key: memoryKey(deployment.id, nil)) : routes,
                          pinTargets: pinTargets, bastionPins: bastionPins,
                          memoryKey: memoryKey(deployment.id, nil))
        }
        guard let node = deployment.nodes.first(where: { $0.id == nodeID }) else {
            throw Failure.unknownMachine
        }

        let id = hostID(of: node)
        let pinned = pins.pin(for: id)
        let parentNode = node.routedThrough.flatMap { parent in
            deployment.nodes.first { $0.id == parent }
        } ?? entryNode
        let parentID = parentNode.map(hostID(of:)) ?? .vps
        let parentEndpoint = parentNode?.endpoint
            ?? HostEndpoint(host: config.vpsHost, port: config.sshPort, user: config.sshUser)
        let relay = TerminalEndpoint.Hop(host: parentEndpoint.host,
                                         port: parentEndpoint.port,
                                         pinnedHostKey: pins.pin(for: parentID),
                                         login: try appLogin(for: deployment, config: config,
                                                             host: parentID))
        var pinTargets: [String: SSHHostID] = [parentEndpoint.host: parentID,
                                               node.endpoint.host: id]
        var routes: [TerminalEndpoint] = []
        if let lan = localAddress(of: node, in: deployment), lan != node.endpoint.host {
            routes.append(TerminalEndpoint(host: lan, port: node.endpoint.port, pinnedHostKey: pinned,
                                           kind: .localNetwork, connectTimeout: localTimeout))
            pinTargets[lan] = id
        }
        routes.append(TerminalEndpoint(host: node.endpoint.host, port: node.endpoint.port,
                                       pinnedHostKey: pinned, parent: relay,
                                       kind: .relay, connectTimeout: publicTimeout, proxy: proxy))
        routes.append(TerminalEndpoint(host: node.endpoint.host, port: node.endpoint.port,
                                       pinnedHostKey: pinned,
                                       kind: .tunnelAddress, connectTimeout: localTimeout))
        let key = memoryKey(deployment.id, node.id)
        routes = allowed(routes, by: HomePathChoice.load(for: deployment.id), routed: node.routedThrough != nil)
        guard !routes.isEmpty else { throw Failure.noLocalAddress }
        return Target(routes: ordered(routes, key: key), pinTargets: pinTargets,
                      bastionPins: bastionPins, memoryKey: key)
    }

    /// Every server this app manages, demos aside
    private static func storedFleet() -> [Deployment] {
        ((try? FileDeploymentStore().load()) ?? []).filter { !DemoServer.isDemo($0) }
    }

    /// Ways into a home network through a managed server
    static func homeDetours(to host: String, port: Int, pinned: String?,
                            from deploymentID: UUID, fleet: [Deployment]) -> [TerminalEndpoint] {
        guard TerminalVPNOffer.isPrivate(host), !fleet.contains(where: { $0.id == deploymentID })
        else { return [] }
        var routes: [TerminalEndpoint] = []
        for server in fleet {
            for node in server.nodes where node.routedThrough != nil && !node.endpoint.host.isEmpty {
                routes += detours(to: host, port: port, pinned: pinned, through: node, of: server)
            }
        }
        return routes
    }

    /// The machine this saved connection goes through
    private static func storedVia(of id: UUID) -> TerminalVia? {
        ((try? TerminalDirectHostStore().load()) ?? []).first { $0.id == id }?.via
    }

    /// Into a network through the chosen machine
    static func chosenRoutes(to host: String, port: Int, pinned: String?,
                             via: TerminalVia, fleet: [Deployment]) -> [TerminalEndpoint] {
        guard let server = fleet.first(where: { $0.id == via.server }),
              let node = via.node.flatMap({ id in server.nodes.first { $0.id == id } }) ?? server.nodes.first,
              !node.endpoint.host.isEmpty
        else { return [] }
        if node.routedThrough != nil {
            return detours(to: host, port: port, pinned: pinned, through: node, of: server)
        }
        let id = hostID(of: node)
        guard let login = try? appLogin(for: server, config: server.dashboardConfig, host: id) else { return [] }
        let jump = TerminalEndpoint.Hop(host: node.endpoint.host, port: node.endpoint.port,
                                        pinnedHostKey: HostKeyPinStore(deploymentID: server.id).pin(for: id),
                                        login: login)
        return [TerminalEndpoint(host: host, port: port, pinnedHostKey: pinned, parent: jump, kind: .relay,
                                 connectTimeout: publicTimeout,
                                 proxy: DashboardSessionFactory.proxy(for: ServerAccessStore.options(for: server.id)))]
    }

    /// The home machine itself, or a neighbour it reaches
    private static func detours(to host: String, port: Int, pinned: String?,
                                through node: DeploymentNode, of server: Deployment) -> [TerminalEndpoint] {
        guard let relay = parentHop(of: node, in: server) else { return [] }
        if names(node, host, in: server) {
            return [TerminalEndpoint(host: node.endpoint.host, port: node.endpoint.port, pinnedHostKey: pinned,
                                     parent: relay, kind: .relay, connectTimeout: publicTimeout,
                                     proxy: DashboardSessionFactory.proxy(for: ServerAccessStore.options(for: server.id))),
                    TerminalEndpoint(host: node.endpoint.host, port: node.endpoint.port, pinnedHostKey: pinned,
                                     kind: .tunnelAddress, connectTimeout: localTimeout)]
        }
        let id = hostID(of: node)
        guard let login = try? appLogin(for: server, config: server.dashboardConfig, host: id) else { return [] }
        let home = TerminalEndpoint.Hop(host: node.endpoint.host, port: node.endpoint.port,
                                        pinnedHostKey: HostKeyPinStore(deploymentID: server.id).pin(for: id),
                                        login: login)
        return [TerminalEndpoint(host: host, port: port, pinnedHostKey: pinned, parent: home, outer: [relay],
                                 kind: .relay, connectTimeout: publicTimeout,
                                 proxy: DashboardSessionFactory.proxy(for: ServerAccessStore.options(for: server.id)))]
    }

    /// The node's parent machine, signed in as the app
    private static func parentHop(of node: DeploymentNode, in server: Deployment) -> TerminalEndpoint.Hop? {
        let parent = node.routedThrough.flatMap { id in server.nodes.first { $0.id == id } } ?? server.nodes.first
        guard let parent, parent.id != node.id else { return nil }
        let id = hostID(of: parent)
        guard let login = try? appLogin(for: server, config: server.dashboardConfig, host: id) else { return nil }
        return TerminalEndpoint.Hop(host: parent.endpoint.host, port: parent.endpoint.port,
                                    pinnedHostKey: HostKeyPinStore(deploymentID: server.id).pin(for: id),
                                    login: login)
    }

    /// Whether a typed address means this machine
    static func names(_ node: DeploymentNode, _ typed: String, in server: Deployment) -> Bool {
        let wanted = bare(typed)
        guard !wanted.isEmpty else { return false }
        var known = [node.endpoint.host, node.name]
        if node.legacySlot == .home { known.append(InstallAddressStore.homeAddress(deploymentID: server.id)) }
        return known.map(bare).contains(wanted)
    }

    /// Lower case, without the `.local` suffix
    private static func bare(_ address: String) -> String {
        let lower = address.trimmingCharacters(in: .whitespaces).lowercased()
        return lower.hasSuffix(".local") ? String(lower.dropLast(6)) : lower
    }

    /// The machine's address on its own network, when known
    private static func localAddress(of node: DeploymentNode, in deployment: Deployment) -> String? {
        guard node.legacySlot == .home else { return nil }
        let typed = InstallAddressStore.homeAddress(deploymentID: deployment.id)
            .trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? nil : typed
    }

    /// A configured jump host, as the terminal signs in
    private static func hop(_ bastion: BastionHop?, _ deployment: Deployment,
                            _ pins: inout [String: String]) -> TerminalEndpoint.Hop? {
        guard let identity = try? KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate(),
              let hop = DashboardSessionFactory.hop(bastion, for: deployment, identity: identity,
                                                    pins: HostKeyPinStore(deploymentID: deployment.id))
        else { return nil }
        pins[hop.host] = hop.endpoint
        let secret: TerminalLogin.Secret = hop.password.map { .password($0) }
            ?? .privateKeySeed(hop.privateKeySeed)
        return TerminalEndpoint.Hop(host: hop.host, port: hop.port, pinnedHostKey: hop.pinnedHostKey,
                                    login: TerminalLogin(username: hop.username, secret: secret))
    }

    // MARK: - The route that worked last

    private static func memoryKey(_ deploymentID: UUID, _ nodeID: UUID?) -> String {
        "terminal.route.\(deploymentID.uuidString).\(nodeID?.uuidString ?? "entry")"
    }

    /// The route that worked last goes first
    static func ordered(_ routes: [TerminalEndpoint], key: String,
                        defaults: UserDefaults = .standard) -> [TerminalEndpoint] {
        guard let raw = defaults.string(forKey: key),
              let kind = TerminalEndpoint.Kind(rawValue: raw),
              let index = routes.firstIndex(where: { $0.kind == kind }), index > 0
        else { return routes }
        var routes = routes
        routes.insert(routes.remove(at: index), at: 0)
        return routes
    }

    /// Routes the chosen path allows
    static func allowed(_ routes: [TerminalEndpoint], by choice: HomePathChoice,
                        routed: Bool) -> [TerminalEndpoint] {
        guard routed else { return routes }
        switch choice {
        case .automatic: return routes
        case .throughVPS: return routes.filter { $0.kind != .localNetwork }
        case .localNetwork: return routes.filter { $0.kind == .localNetwork }
        }
    }

    /// Which path the machine's row reports
    static func pathInUse(choice: HomePathChoice, deploymentID: UUID, nodeID: UUID,
                          defaults: UserDefaults = .standard) -> HomePathChoice {
        guard choice == .automatic else { return choice }
        let last = defaults.string(forKey: memoryKey(deploymentID, nodeID))
        return last == TerminalEndpoint.Kind.localNetwork.rawValue ? .localNetwork : .throughVPS
    }

    static func remember(_ route: TerminalEndpoint, key: String,
                         defaults: UserDefaults = .standard) {
        defaults.set(route.kind.rawValue, forKey: key)
    }

    static func appLogin(for deployment: Deployment,
                         config: DashboardConfig,
                         host: SSHHostID = .vps) throws -> TerminalLogin {
        if deployment.usesPasswordAuth {
            guard let password = DashboardPasswordStore(deploymentID: deployment.id).load(for: host) else {
                throw Failure.notConfigured
            }
            return TerminalLogin(username: config.sshUser, secret: .password(password))
        }
        let identity = try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
        return TerminalLogin(username: config.sshUser,
                             secret: .privateKeySeed(identity.privateKeySeed))
    }

    static func login(for profile: TerminalProfile, deployment: Deployment) throws -> TerminalLogin {
        switch profile.secret {
        case .password(let password):
            return TerminalLogin(username: profile.username, secret: .password(password))
        case .privateKeySeed(let seed):
            return TerminalLogin(username: profile.username, secret: .privateKeySeed(seed))
        case .appKey:
            let node = deployment.nodes.first { $0.id == profile.nodeID }
            let appUser = node.map { $0.endpoint.user.isEmpty ? deployment.dashboardConfig.sshUser : $0.endpoint.user }
                ?? deployment.dashboardConfig.sshUser
            if deployment.usesPasswordAuth, profile.username == appUser {
                let app = try appLogin(for: deployment, config: deployment.dashboardConfig,
                                       host: node.map(hostID(of:)) ?? .vps)
                return TerminalLogin(username: profile.username, secret: app.secret)
            }
            let identity = try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
            return TerminalLogin(username: profile.username,
                                 secret: .privateKeySeed(identity.privateKeySeed))
        }
    }

    private static func hostID(of node: DeploymentNode) -> SSHHostID {
        if let slot = node.legacySlot { return SSHHostID(kind: .slot(slot)) }
        return SSHHostID(kind: .node(node.id))
    }
}
