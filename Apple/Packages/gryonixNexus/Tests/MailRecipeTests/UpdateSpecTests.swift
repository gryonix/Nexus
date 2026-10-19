import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// `UpdateSpec` pinned against the GENERATED artifacts
final class UpdateSpecTests: XCTestCase {
    private func input(services: Set<ServiceID>) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .ubuntu)],
            dashboardAccess: DashboardAccessInput(
                sshUser: "admin",
                appPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"),
            services: services,
            serviceSettings: ServiceSettings(minecraftJavaAcceptsEULA: true,
                                             minecraftBedrockAcceptsEULA: true,
                                             machineAtHome: true,
                                             homeAssistantUSBDevice: "/dev/ttyACM0")
        )
    }

    private func script(_ services: Set<ServiceID>) throws -> String {
        var wanted = services
        // An add-on is never installed without the hub
        if !wanted.isDisjoint(with: ServiceID.smartHomeAddOns) { wanted.insert(.homeAssistant) }
        let bundle = try MailRecipe().generate(from: try input(services: wanted))
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    private var context: ServiceContext {
        ServiceContext(domain: "example.com", sshUser: "admin")
    }

    func testEveryImageInTheSpecIsAnImageTheSetupActuallyPulls() throws {
        for service in ServiceRegistry.all {
            let spec = service.updateSpec(context)
            guard !spec.images.isEmpty else { continue }
            let text = try script([service.id])
            for image in spec.images {
                XCTAssertTrue(text.contains(image),
                              "\(service.id.rawValue) declares \(image), which its setup never mentions")
            }
        }
    }

    func testEveryImageInAServicesComposeFileIsCoveredByItsSpec() throws {
        for service in ServiceRegistry.all {
            let spec = service.updateSpec(context)
            // Services that update themselves name no images on purpose.
            guard spec.flavour == .composePull else { continue }
            guard let compose = service.composeFile(context) else { continue }
            for image in Self.imageReferences(in: compose.composeContents) {
                XCTAssertTrue(spec.images.contains(image),
                              "\(service.id.rawValue) runs \(image), which its updateSpec does not list")
            }
        }
    }

    func testTheUnpollableFlavoursDoNotSmuggleInARegistryImage() throws {
        for service in ServiceRegistry.all {
            let spec = service.updateSpec(context)
            switch spec.flavour {
            case .composePull:
                XCTAssertFalse(spec.images.isEmpty,
                               "\(service.id.rawValue) pulls its updates but names no image to check")
            case .ownUpdater:
                XCTAssertTrue(spec.images.isEmpty,
                              "\(service.id.rawValue) is updated by its own updater, so a list of images here is a second source of truth")
            case .builtOnServer:
                for image in spec.images {
                    XCTAssertTrue(image.hasSuffix(":local"),
                                  "\(service.id.rawValue) claims \(image) is built on the server, but that is a registry tag")
                }
            }
        }
    }

    private static func imageReferences(in compose: String) -> [String] {
        compose.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), line.hasPrefix("image:") else { return nil }
            let value = line.dropFirst("image:".count).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !value.contains("$") else { return nil }
            return value
        }
    }
}
