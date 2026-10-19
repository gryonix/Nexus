import gryonixNexusCore
import ServerControl
import ServiceCatalog

/// A deployment's Cloudflare Tunnel: its connector token and its names
enum TunnelSetup {
    /// One tunnel per deployment, named after its domain
    static func name(of deployment: Deployment) -> String {
        "gryonixnexus-" + deployment.domain.replacingOccurrences(of: ".", with: "-")
    }

    /// The credential the server's connector runs with
    static func connectorToken(for deployment: Deployment) async throws -> String {
        let provider = try await provider(token: tunnelToken())
        do {
            let tunnel = try await provider.findOrCreateTunnel(named: name(of: deployment))
            return try await provider.connectorToken(tunnelID: tunnel)
        } catch CloudflareError.invalidToken {
            throw tokenMissing
        }
    }

    /// Routes every web name through the tunnel; returns the count
    static func publishNames(of deployment: Deployment) async throws -> Int {
        let token = try await tunnelToken()
        let provider = try await provider(token: token)
        let tunnel = try await provider.findOrCreateTunnel(named: name(of: deployment))
        let names = webNames(of: deployment)
        try await provider.applyIngress(tunnelID: tunnel, routes: names.map { TunnelRoute(hostname: $0) })
        let own = names.filter { $0.hasSuffix(".\(deployment.domain)") }
        let dnsToken = await DNSCredentialTokenStore.currentCloudflareDNSToken()
        let records = CloudflareTunnelProvider(token: dnsToken ?? token, accountID: "")
        try await records.publishHostnames(own, tunnelID: tunnel, zone: deployment.domain)
        return own.count
    }

    /// Web names to route through the tunnel, never mail hosts
    static func webNames(of deployment: Deployment) -> [String] {
        let context = deployment.serviceContext
        var names: [String] = []
        for service in deployment.installedServices where !ServiceRegistry.mailEngineIDs.contains(service.id) {
            guard let ingress = service.webIngress(context) else { continue }
            for name in context.servedHostnames(of: ingress.hostname)
            where !names.contains(name) && !name.hasPrefix("mail.") {
                names.append(name)
            }
        }
        return names
    }

    static var tokenMissing: ServerControlError {
        .notConfigured(UIL10n.string(
            "Add a Cloudflare API token with tunnel permission before installing the tunnel."))
    }

    private static func tunnelToken() async throws -> String {
        guard let token = await DNSCredentialTokenStore.currentCloudflareTunnelToken() else {
            throw tokenMissing
        }
        return token
    }

    /// Provider for the tunnel token; account read via DNS token
    private static func provider(token: String) async throws -> CloudflareTunnelProvider {
        if let dns = await DNSCredentialTokenStore.currentCloudflareDNSToken(),
           let account = try? await CloudflareTunnelProvider.accountID(token: dns) {
            return CloudflareTunnelProvider(token: token, accountID: account)
        }
        let account = try await CloudflareTunnelProvider.accountID(token: token)
        return CloudflareTunnelProvider(token: token, accountID: account)
    }
}
