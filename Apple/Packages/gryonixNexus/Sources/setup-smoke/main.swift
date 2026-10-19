import Foundation
import gryonixNexusCore
import ServiceCatalog
import MailRecipe

struct SmokeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Keeps the WireGuard keypairs stable across regenerations
struct CachedWireGuardKeyProvider: WireGuardKeyProvider {
    let path: String
    private let inner = CryptoKitWireGuardKeyProvider()

    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        var cache = loadCache()
        if let stored = cache[slot.rawValue],
           let priv = stored["private"], let pub = stored["public"] {
            return WireGuardKeyPair(privateKey: priv, publicKey: pub)
        }
        let pair = try inner.makeKeyPair(for: slot)
        cache[slot.rawValue] = ["private": pair.privateKey, "public": pair.publicKey]
        try save(cache)
        return pair
    }

    private func loadCache() -> [String: [String: String]] {
        guard let data = FileManager.default.contents(atPath: path),
              let parsed = try? JSONSerialization.jsonObject(with: data)
                as? [String: [String: String]] else { return [:] }
        return parsed
    }

    private func save(_ cache: [String: [String: String]]) throws {
        let data = try JSONSerialization.data(withJSONObject: cache,
                                              options: [.prettyPrinted, .sortedKeys])
        FileManager.default.createFile(atPath: path, contents: data,
                                       attributes: [.posixPermissions: 0o600])
    }
}

let env = ProcessInfo.processInfo.environment

func required(_ key: String) throws -> String {
    guard let value = env[key], !value.isEmpty else {
        throw SmokeError("set \(key)")
    }
    return value
}

func distribution(_ key: String) throws -> DistributionProfileID {
    let raw = env[key] ?? "ubuntu"
    guard let value = DistributionProfileID(rawValue: raw) else {
        throw SmokeError("\(key): unknown distribution '\(raw)'")
    }
    return value
}

func smokeServers(topology: Topology, publicAddress: NetworkAddress) throws -> [ServerNode] {
    switch topology {
    case .singleHost:
        return [ServerNode(role: .singleHost, publicAddress: publicAddress,
                              distribution: try distribution("SETUP_DISTRO"))]
    case .vpsRelayWithHomeBackend:
        return [
            ServerNode(role: .vpsRelay, publicAddress: publicAddress,
                       vpnAddress: .ipv4("10.8.0.1"),
                       distribution: try distribution("SETUP_VPS_DISTRO")),
            ServerNode(role: .homeBackend, publicAddress: nil,
                       vpnAddress: .ipv4("10.8.0.2"),
                       distribution: try distribution("SETUP_HOME_DISTRO"))
        ]
    }
}

func writeBundle(_ input: MailRecipeInput, outDir: String) throws {
    try FileManager.default.createDirectory(atPath: outDir,
                                            withIntermediateDirectories: true)

    let keyCache = env["SETUP_WG_KEYS"]
        ?? (outDir as NSString).appendingPathComponent("wireguard-keys.json")
    let bundle = try MailRecipe(keyProvider: CachedWireGuardKeyProvider(path: keyCache))
        .generate(from: input)
    for artifact in bundle.artifacts {
        let path = (outDir as NSString).appendingPathComponent(artifact.fileName)
        try artifact.contents.write(toFile: path, atomically: true, encoding: .utf8)
        print("· \(artifact.fileName)  (\(artifact.contents.count) bytes)"
              + (artifact.server.map { "  → \($0.rawValue)" } ?? ""))
    }
    print("── \(bundle.artifacts.count) artifacts in \(outDir)")
}

func run() throws {
    let domain = try Domain(try required("SETUP_DOMAIN"))
    let aliases = try (env["SETUP_ALIASES"] ?? "")
        .split(separator: ",")
        .map { try Domain(String($0)) }
    let hostname = env["SETUP_HOSTNAME"] ?? "mail.\(domain.name)"
    let sshUser = env["SETUP_SSH_USER"] ?? DashboardAccessInput.defaultUser
    let outDir = try required("SETUP_OUT")

    let keyPath = (try required("SETUP_APP_KEY_FILE") as NSString).expandingTildeInPath
    let appKey = try String(contentsOfFile: keyPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let services = Set((env["SETUP_SERVICES"] ?? "mailcow,vaultwarden")
        .split(separator: ",")
        .map { ServiceID(rawValue: String($0).trimmingCharacters(in: .whitespaces)) })
    for id in services where ServiceRegistry.service(id) == nil {
        throw SmokeError("unknown service: \(id.rawValue)")
    }

    let language = AppLanguage(rawValue: env["SETUP_LANG"] ?? "en") ?? .en
    let topology: Topology = (env["SETUP_TOPOLOGY"] ?? "B").uppercased() == "A"
        ? .singleHost : .vpsRelayWithHomeBackend
    let scope: DeploymentScope = (env["SETUP_SCOPE"] ?? "public").lowercased() == "local"
        ? .localOnly : .publicInternet

    let publicAddress = try NetworkAddress(parsing: try required("SETUP_VPS_PUBLIC"))

    let servers = try smokeServers(topology: topology, publicAddress: publicAddress)

    var settings = ServiceSettings()
    if let port = env["SETUP_WG_PORT"].flatMap(Int.init) {
        settings.wireguardVPNPort = port
    } else if topology == .vpsRelayWithHomeBackend, services.contains(.wireguardVPN) {
        settings.wireguardVPNPort = 51821
    }

    let input = MailRecipeInput(
        domain: domain,
        additionalDomains: aliases,
        hostname: hostname,
        topology: topology,
        scope: scope,
        servers: servers,
        dashboardAccess: DashboardAccessInput(sshUser: sshUser, appPublicKey: appKey),
        services: services,
        serviceSettings: settings,
        language: language)

    try writeBundle(input, outDir: outDir)
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("setup-smoke: \(error)\n".utf8))
    exit(1)
}
