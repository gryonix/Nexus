import Foundation
import ServerControl
import ServerControlSSH

enum DashboardSessionFactory {
    /// Off-main construction
    static func makeRunnerDetached(deployment: Deployment,
                                   shared: Bool = true) async throws
        -> any SSHCommandRunner & RemoteFileBrowser {
        if DemoFleet.covers(deployment) { return DemoCommandRunner(deployment: deployment) }
        return try await Task.detached(priority: .userInitiated) {
            try makeSSHRunner(deployment: deployment, shared: shared)
        }.value
    }

    static func makeRunner(deployment: Deployment) throws -> any SSHCommandRunner & RemoteFileBrowser {
        if DemoFleet.covers(deployment) {
            return DemoCommandRunner(deployment: deployment)
        }
        return try makeSSHRunner(deployment: deployment)
    }

    private struct ConnectionFingerprint: Equatable {
        let config: DashboardConfig
        let usesPasswordAuth: Bool
        let nodes: String
        let access: ServerAccessOptions

        init(_ deployment: Deployment) {
            config = deployment.dashboardConfig
            usesPasswordAuth = deployment.usesPasswordAuth
            nodes = deployment.nodes
                .map { "\($0.id)@\($0.sshHost)" }
                .joined(separator: ",")
            access = ServerAccessStore.options(for: deployment.id)
        }
    }

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cache: [UUID: (ConnectionFingerprint, CitadelCommandRunner)] = [:]

    static func invalidate(deploymentID: UUID) {
        cacheLock.lock()
        let dropped = cache.removeValue(forKey: deploymentID)?.1
        cacheLock.unlock()
        if let dropped { Task.detached { await dropped.disconnect() } }
    }

    /// Hangs up everything
    static func invalidateAll() {
        cacheLock.lock()
        let dropped = cache.values.map(\.1)
        cache.removeAll()
        cacheLock.unlock()
        Task.detached { for runner in dropped { await runner.disconnect() } }
    }

    static func isShared(_ runner: any SSHCommandRunner, deploymentID: UUID) -> Bool {
        cacheLock.lock()
        let cached = cache[deploymentID]?.1
        cacheLock.unlock()
        guard let cached else { return false }
        return (runner as AnyObject) === (cached as AnyObject)
    }

    static func release(_ runner: (any SSHCommandRunner)?, deploymentID: UUID) async {
        guard let runner, !isShared(runner, deploymentID: deploymentID) else { return }
        await runner.disconnect()
    }

    private static func hop(_ bastion: BastionHop?,
                            for deployment: Deployment,
                            identity: AppSSHIdentity,
                            pins: HostKeyPinStore) -> SSHConnectionSettings.Hop? {
        guard let bastion, bastion.isUsable else { return nil }
        if let id = bastion.fleetServerID {
            guard let server = (try? FileDeploymentStore().load())?.first(where: { $0.id == id })
            else { return nil }
            let seed = (try? KeychainSSHIdentityStore(deploymentID: server.id).loadOrGenerate())?
                .privateKeySeed ?? identity.privateKeySeed
            let password = server.usesPasswordAuth
                ? DashboardPasswordStore(deploymentID: server.id).load(for: .vps)
                : nil
            let endpoint = "\(server.entry.host):\(server.entry.port)"
            return .init(host: server.entry.host,
                         port: server.entry.port,
                         username: server.entry.user,
                         privateKeySeed: seed,
                         password: password,
                         pinnedHostKey: HostKeyPinStore(deploymentID: server.id).pin(for: .vps)
                             ?? pins.pin(forBastion: endpoint))
        }
        guard let manual = bastion.manual, manual.isValid else { return nil }
        return .init(host: manual.host,
                     port: manual.port,
                     username: manual.user,
                     privateKeySeed: identity.privateKeySeed,
                     password: nil,
                     pinnedHostKey: pins.pin(forBastion: "\(manual.host):\(manual.port)"))
    }

    private static func makeSSHRunner(deployment: Deployment,
                                      shared: Bool = true) throws -> CitadelCommandRunner {
        try LicenseGate.check(deployment)
        let fingerprint = ConnectionFingerprint(deployment)
        if shared {
            cacheLock.lock()
            let cached = cache[deployment.id]
            cacheLock.unlock()
            if let cached, cached.0 == fingerprint { return cached.1 }
        }
        let config = deployment.dashboardConfig
        guard config.isConnectable else {
            throw ServerControlError.notConfigured(UIL10n.string("specify the server address and SSH user in the server settings"))
        }
        let identity = try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
        let pins = HostKeyPinStore(deploymentID: deployment.id)
        var passwords: [SSHHostID: String] = [:]
        if deployment.usesPasswordAuth {
            let store = DashboardPasswordStore(deploymentID: deployment.id)
            for node in deployment.nodes {
                guard let password = store.load(for: node.sshHost) else {
                    throw ServerControlError.notConfigured(
                        UIL10n.string("enter the user's password in the server settings"))
                }
                passwords[node.sshHost] = password
            }
        }
        var settings = SSHConnectionSettings.make(
            config: config,
            identity: identity,
            passwords: passwords,
            pinnedVPSHostKey: pins.pin(for: .vps),
            pinnedHomeHostKey: pins.pin(for: .home),
            homeLANHost: InstallAddressStore.homeAddress(deploymentID: deployment.id)
        )
        settings.additionalNodes = SSHConnectionSettings.additionalNodes(of: deployment) {
            pins.pin(for: $0)
        }
        let access = ServerAccessStore.options(for: deployment.id)
        settings.bastion = hop(access.bastion, for: deployment, identity: identity, pins: pins)
        if let fallback = access.fallback, fallback.isUsable {
            let endpoint = fallback.endpoint(primary: deployment.entry)
            settings.entryFallback = .init(
                host: endpoint.host,
                port: endpoint.port,
                bastion: hop(fallback.bastion, for: deployment, identity: identity, pins: pins))
        }
        if let profile = ProxyStore.profile(access.proxyID), profile.isUsable {
            settings.proxy = ProxyConnect.Endpoint(
                kind: profile.kind == .socks5 ? .socks5 : .httpConnect,
                host: profile.host.trimmingCharacters(in: .whitespaces),
                port: profile.port,
                username: profile.username.isEmpty ? nil : profile.username,
                password: ProxyPasswordStore.password(profile.id))
        }
        let runner = CitadelCommandRunner(settings: settings) { host, presentedKey in
            pins.store(presentedKey, for: host)
        } onPinBastionHostKey: { endpoint, presentedKey in
            pins.store(presentedKey, forBastion: endpoint)
        }
        guard shared else { return runner }
        cacheLock.lock()
        if let raced = cache[deployment.id], raced.0 == fingerprint {
            cacheLock.unlock()
            return raced.1
        }
        let replaced = cache[deployment.id]?.1
        cache[deployment.id] = (fingerprint, runner)
        cacheLock.unlock()
        if let replaced { Task.detached { await replaced.disconnect() } }
        return runner
    }
}
