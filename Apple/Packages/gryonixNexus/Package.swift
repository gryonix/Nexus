// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "gryonixNexus",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ServiceCatalog", targets: ["ServiceCatalog"]),
        // The core, independent of any concrete recipe.
        .library(name: "gryonixNexusCore", targets: ["gryonixNexusCore"]),
        .library(name: "MailRecipe", targets: ["MailRecipe"]),
        // Server dashboard logic: commands, parsers, operations. Zero dependencies.
        .library(name: "ServerControl", targets: ["ServerControl"]),
        .library(name: "ServerControlSSH", targets: ["ServerControlSSH"]),
        .library(name: "AgentClient", targets: ["AgentClient"]),
        .library(name: "AgentClientSSH", targets: ["AgentClientSSH"]),
        .library(name: "AgentControl", targets: ["AgentControl"]),
        .library(name: "VPNProfile", targets: ["VPNProfile"]),
        .library(name: "VPNTunnel", targets: ["VPNTunnel"])
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", .upToNextMinor(from: "0.12.0")),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(name: "ServiceCatalog"),
        .target(name: "gryonixNexusCore", dependencies: ["ServiceCatalog"]),
        .target(name: "MailRecipe", dependencies: ["gryonixNexusCore", "ServiceCatalog"]),
        .target(name: "ServerControl", dependencies: ["ServiceCatalog", "gryonixNexusCore"]),
        .target(name: "ServerControlSSH", dependencies: [
            "ServerControl",
            .product(name: "Citadel", package: "Citadel")
        ]),
        .target(name: "AgentClient", dependencies: [
            .product(name: "SwiftProtobuf", package: "swift-protobuf")
        ]),
        .target(name: "AgentClientSSH", dependencies: [
            "AgentClient",
            .product(name: "Citadel", package: "Citadel")
        ]),
        .target(name: "AgentControl", dependencies: [
            "AgentClient",
            "ServerControl",
            "ServiceCatalog"
        ]),
        .target(name: "VPNProfile", dependencies: ["ServiceCatalog"]),
        // Real traffic through Network Extension
        .target(name: "VPNTunnel", dependencies: ["ServiceCatalog", "VPNProfile"],
                swiftSettings: [.define("GRYONIX_SYSTEM_TUNNEL")]),
        .executableTarget(name: "handoff-golden", dependencies: ["VPNProfile", "ServiceCatalog"]),

        .executableTarget(name: "proxy-link-golden", dependencies: ["VPNProfile"]),
        .executableTarget(name: "xray-config-golden", dependencies: ["VPNProfile"]),
        .executableTarget(name: "agent-smoke", dependencies: [
            "AgentClient",
            "AgentClientSSH",
            "AgentControl",
            "ServerControl",
            "ServiceCatalog",
            .product(name: "Citadel", package: "Citadel"),
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .executableTarget(name: "setup-smoke", dependencies: [
            "gryonixNexusCore",
            "ServiceCatalog",
            "MailRecipe"
        ]),
        .executableTarget(name: "ssh-probe", dependencies: [
            "ServerControl",
            "ServerControlSSH",
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .executableTarget(name: "mailbox-smoke", dependencies: [
            "ServerControl",
            "ServerControlSSH",
            "ServiceCatalog",
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .testTarget(name: "ServiceCatalogTests", dependencies: ["ServiceCatalog", "MailRecipe"]),
        .testTarget(name: "gryonixNexusCoreTests", dependencies: ["gryonixNexusCore"]),
        .testTarget(name: "MailRecipeTests", dependencies: ["MailRecipe"]),
        .testTarget(name: "ServerControlTests", dependencies: ["ServerControl"]),
        .testTarget(name: "ServerControlSSHTests", dependencies: ["ServerControlSSH"]),
        .testTarget(name: "AgentClientTests", dependencies: ["AgentClient"]),
        .testTarget(name: "AgentControlTests", dependencies: ["AgentControl", "ServiceCatalog"]),
        .testTarget(name: "VPNProfileTests", dependencies: ["VPNProfile", "ServiceCatalog"]),
        .testTarget(name: "VPNTunnelTests",
                    dependencies: ["VPNTunnel", "VPNProfile", "ServiceCatalog"],
                    resources: [.process("Resources")])
    ]
)
