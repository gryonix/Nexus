import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

private final class LintFixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        WireGuardKeyPair(privateKey: "TEST-PRIVATE-KEY=", publicKey: "TEST-PUBLIC-KEY=")
    }
}

final class GeneratedScriptLintTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFakeFake gryonixnexus-app"

    private struct Variant {
        let name: String
        let input: MailRecipeInput
    }

    private func makeVariants() throws -> [Variant] {
        var variants: [Variant] = []
        for (setName, services) in Self.serviceSets {
            for withAccess in [false, true] {
                for language in [AppLanguage.en, .ru] {
                    variants += try topologyVariants(setName: setName, services: services,
                                                     withAccess: withAccess, language: language)
                }
            }
        }
        variants += try multidomainVariants()
        variants.append(try gpuVariant())
        return variants
    }

    private static let serviceSets: [(String, Set<ServiceID>)] = [
        ("bare", []),
        ("mailcow", [.mailcow]),
        ("nomail", [.vaultwarden, .nextcloud, .immich, .forgejo, .gitlab]),
        ("mailcow-wg", [.mailcow, .vaultwarden, .nextcloud, .immich, .wireguardVPN]),
        ("mailcow-awg", [.mailcow, .vaultwarden, .nextcloud, .immich, .forgejo, .amneziaWG]),
        ("nomail-ss", [.vaultwarden, .shadowsocks]),
        ("mailcow-xray", [.mailcow, .vaultwarden, .xrayReality]),
        ("nomail-ovpn", [.vaultwarden, .openVPN]),
        ("mailu", [.mailu]),
        ("dms", [.dockerMailserver]),
        ("dms-full", [.dockerMailserver, .vaultwarden, .forgejo, .wireguardVPN]),
        ("mailu-full", [.mailu, .vaultwarden, .nextcloud, .immich, .forgejo, .wireguardVPN]),
        ("jellyfin", [.jellyfin]),
        ("jellyfin-full", [.jellyfin, .vaultwarden, .nextcloud, .wireguardVPN]),
        ("adguard", [.adguardHome]),
        ("adguard-full", [.adguardHome, .vaultwarden, .nextcloud, .wireguardVPN]),
        ("pihole", [.pihole]),
        ("pihole-full", [.pihole, .vaultwarden, .nextcloud, .wireguardVPN]),
        ("authelia", [.authelia]),
        ("authelia-guarding", [.authelia, .adguardHome, .homepage, .vaultwarden]),
        ("homepage", [.homepage]),
        ("homepage-full", [.homepage, .mailcow, .vaultwarden, .nextcloud, .seafile,
                           .immich, .jellyfin, .forgejo, .adguardHome, .wireguardVPN]),
        ("photoprism", [.photoprism]),
        ("photoprism-immich", [.photoprism, .immich, .vaultwarden]),
        ("seafile", [.seafile]),
        ("seafile-nextcloud", [.seafile, .nextcloud, .vaultwarden]),
        ("psono", [.psono]),
        ("psono-vaultwarden", [.psono, .vaultwarden]),
        ("passbolt", [.passbolt]),
        ("passwords-shelf", [.passbolt, .psono, .vaultwarden]),
        ("mesh", [.headscale]),
        ("mesh-full", [.headscale, .vaultwarden, .nextcloud, .wireguardVPN]),
        ("tunnel", [.cloudflared]),
        ("tunnel-adguard", [.cloudflared, .adguardHome]),
        ("minecraft", [.minecraftJava]),
        ("minecraft-both", [.minecraftJava, .minecraftBedrock, .vaultwarden]),
        ("ai", [.openWebUI, .ollama]),
        ("ai-remote", [.openWebUI]),
        ("ai-gateway", [.openWebUI, .ollama, .liteLLM]),
        ("ai-gateway-only", [.liteLLM]),
        ("automation", [.n8n]),
        ("automation-full", [.n8n, .openWebUI, .ollama, .vaultwarden]),
        ("smart-home", [.homeAssistant]),
        ("rag", [.anythingLLM, .openWebUI, .ollama]),
        ("rag-qdrant", [.anythingLLM, .qdrant, .liteLLM]),
        ("ai-search", [.openWebUI, .ollama, .searxng]),
        ("ai-agent", [.openclaw, .liteLLM])
    ]

    private static let lintSettings = ServiceSettings(minecraftJavaVersion: "1.21.4",
                                   minecraftJavaAcceptsEULA: true,
                                   minecraftJavaWhitelist: "dana,alex",
                                   minecraftJavaOperators: "dana",
                                   minecraftBedrockAcceptsEULA: true,
                                   wireguardVPNPort: 51821, xrayRealityPort: 8443,
                                   machineAtHome: true)

    private static let singleHostServers = [
        ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)
    ]

    private static let splitServers = [
        ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                   vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
        ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .ubuntu)
    ]

    /// Scenario A and scenario B for one service set.
    private func topologyVariants(setName: String, services: Set<ServiceID>,
                                  withAccess: Bool, language: AppLanguage) throws -> [Variant] {
        let access = withAccess ? DashboardAccessInput(sshUser: "admin", appPublicKey: appKey) : nil
        let suffix = "\(setName)-\(withAccess ? "access" : "noaccess")-\(language.rawValue)"
        let shapes: [(String, Topology, [ServerNode])] = [
            ("A", .singleHost, Self.singleHostServers),
            ("B", .vpsRelayWithHomeBackend, Self.splitServers)
        ]
        return try shapes.map { prefix, topology, servers in
            Variant(name: "\(prefix)-\(suffix)",
                    input: MailRecipeInput(domain: try Domain("example.com"),
                                           hostname: "mail.example.com",
                                           topology: topology,
                                           servers: servers,
                                           dashboardAccess: access,
                                           services: services,
                                           serviceSettings: Self.lintSettings,
                                           language: language))
        }
    }

    private func multidomainVariants() throws -> [Variant] {
        let shapes: [(String, Topology, [ServerNode])] = [
            ("A-multidomain", .singleHost, Self.singleHostServers),
            ("B-multidomain", .vpsRelayWithHomeBackend, Self.splitServers)
        ]
        return try shapes.map { name, topology, servers in
            Variant(name: name,
                    input: MailRecipeInput(
                        domain: try Domain("example.com"),
                        additionalDomains: [try Domain("example.org"), try Domain("example.net")],
                        hostname: "mail.example.com",
                        topology: topology,
                        servers: servers,
                        dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: appKey),
                        services: [.mailcow, .vaultwarden, .nextcloud, .immich, .forgejo, .gitlab,
                                   .amneziaWG],
                        serviceSettings: Self.lintSettings,
                        language: .en))
        }
    }

    private func gpuVariant() throws -> Variant {
        Variant(name: "A-ai-gpu",
                input: MailRecipeInput(domain: try Domain("example.com"),
                                       hostname: "mail.example.com",
                                       topology: .singleHost,
                                       servers: Self.singleHostServers,
                                       dashboardAccess: DashboardAccessInput(sshUser: "admin",
                                                                             appPublicKey: appKey),
                                       services: [.openWebUI, .ollama],
                                       serviceSettings: ServiceSettings(ollamaUsesGPU: true),
                                       language: .en))
    }

    func testEveryGeneratedScriptPassesBashSyntaxCheck() throws {
        #if os(macOS)
        let dumpDir = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DUMP_DIR"]
        if let dumpDir {
            try FileManager.default.createDirectory(atPath: dumpDir, withIntermediateDirectories: true)
        }
        let recipe = MailRecipe(keyProvider: LintFixedKeyProvider())
        var checked = 0
        for variant in try makeVariants() {
            let bundle = try recipe.generate(from: variant.input)
            for artifact in bundle.artifacts + bundle.serviceScripts {
                if let dumpDir {
                    let url = URL(fileURLWithPath: dumpDir)
                        .appendingPathComponent("\(variant.name)__\(artifact.fileName)")
                    try artifact.contents.write(to: url, atomically: true, encoding: .utf8)
                }
                guard artifact.kind == .shellScript else { continue }
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("gryonixnexus-lint-\(UUID().uuidString).sh")
                try artifact.contents.write(to: tmp, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(at: tmp) }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-n", tmp.path]
                let stderr = Pipe()
                process.standardError = stderr
                try process.run()
                process.waitUntilExit()
                let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                       encoding: .utf8) ?? ""
                XCTAssertEqual(process.terminationStatus, 0,
                               "\(variant.name)/\(artifact.fileName): bash -n failed\n\(errorText)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "no scripts were generated")
        #endif
    }
}
