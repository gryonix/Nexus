import ServerControl
import XCTest

@testable import gryonixNexus

final class DeploymentTransferFormatTests: XCTestCase {
    private let deploymentID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func pair() -> Deployment {
        Deployment(id: deploymentID, name: "Home mail", topology: .vpsRelayWithHomeBackend,
                   domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
                   homeWGAddress: "10.8.0.2",
                   services: [.mailcow])
    }

    // MARK: - The names in the file

    func testTheTwoShippedMachinesAreStillNamedVpsAndHome() {
        XCTAssertEqual(InstallAddressStore.machineName(.vps), "vps")
        XCTAssertEqual(InstallAddressStore.machineName(.home), "home")
        XCTAssertEqual(InstallAddressStore.machine(named: "vps"), .vps)
        XCTAssertEqual(InstallAddressStore.machine(named: "home"), .home)
    }

    func testAMachineWithoutASlotIsNamedByItsNodeID() {
        let id = UUID()
        XCTAssertEqual(InstallAddressStore.machineName(.node(id)), id.uuidString)
        XCTAssertEqual(InstallAddressStore.machine(named: id.uuidString), .node(id))
    }

    func testTwoDifferentMachinesNeverShareAName() {
        let deployment = pair()
        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: deployment.ingressNode?.id)
        var names = (deployment.derivedNodes + [extra]).map { InstallAddressStore.machineName($0.sshHost) }
        names.append(InstallAddressStore.machineName(.node(UUID())))
        XCTAssertEqual(Set(names).count, names.count, "two machines answered to one name: \(names)")
    }

    func testAnUnplaceableNameIsRefusedRatherThanFallingBackToTheEntryMachine() {
        XCTAssertNil(InstallAddressStore.machine(named: "relay"))
        XCTAssertNil(InstallAddressStore.machine(named: ""))
        XCTAssertNil(InstallAddressStore.machine(named: "node:not-a-uuid"))
    }

    // MARK: - A file written before this slice

    private var preSliceBundle: Data {
        let json = """
        {
          "version" : 1,
          "deployment" : {
            "additionalDomains" : [],
            "domain" : "example.com",
            "entry" : { "host" : "203.0.113.4", "port" : 22, "user" : "admin" },
            "homeWGAddress" : "10.8.0.2",
            "id" : "\(deploymentID.uuidString)",
            "name" : "Home mail",
            "scope" : "publicInternet",
            "serviceSettings" : {},
            "services" : ["mailcow"],
            "tags" : [],
            "timeouts" : {
              "longSeconds" : 600, "quickSeconds" : 15,
              "restartSeconds" : 60, "serviceRestartSeconds" : 120
            },
            "topology" : "vpsRelayWithHomeBackend",
            "usesAgent" : false,
            "usesPasswordAuth" : false,
            "wgInterface" : "wg0"
          },
          "dashboardPassword" : "one-password-for-everything",
          "hostKeyPins" : { "home" : "ssh-ed25519 HOME", "vps" : "ssh-ed25519 VPS" },
          "installUsers" : { "home" : "ops", "vps" : "root" },
          "reports" : [],
          "wireGuardSeeds" : {}
        }
        """
        return Data(json.utf8)
    }

    func testABundleWrittenBeforeThisSliceStillImports() throws {
        let transfer = try DeploymentTransferService.decode(preSliceBundle)

        XCTAssertEqual(transfer.version, 1)
        XCTAssertEqual(transfer.deployment.id, deploymentID,
                       "the id is what every secret is keyed by — it must survive the move")
        XCTAssertEqual(transfer.deployment.topology, .vpsRelayWithHomeBackend,
                       "the stored enum still decodes; the generator picks the install shape with it")
        XCTAssertNil(transfer.deployment.storedNodes,
                     "a pair has no node list, then or now — its machines are derived")
        XCTAssertNil(transfer.deployment.placement)
        XCTAssertEqual(transfer.hostKeyPins["vps"], "ssh-ed25519 VPS")
        XCTAssertEqual(transfer.hostKeyPins["home"], "ssh-ed25519 HOME")
        XCTAssertEqual(transfer.installUsers?["home"], "ops")
        XCTAssertEqual(transfer.dashboardPassword, "one-password-for-everything")
        XCTAssertNil(transfer.dashboardPasswords,
                     "the per-machine map postdates this file; the single password is what it means")
    }

    func testThePinsInAPreSliceBundleStillNameThisDeploymentsMachines() throws {
        let transfer = try DeploymentTransferService.decode(preSliceBundle)
        let names = transfer.deployment.nodes.map { InstallAddressStore.machineName($0.sshHost) }
        XCTAssertEqual(names, ["vps", "home"])
        for name in names {
            XCTAssertNotNil(transfer.hostKeyPins[name],
                            "\(name)'s pin is in the file but the machine is looked up under another name")
        }
    }

    func testRoundTrippingAPreSliceBundleAddsNoNodeListAndNoPlacement() throws {
        let transfer = try DeploymentTransferService.decode(preSliceBundle)
        let text = String(decoding: try DeploymentTransferService.encode(transfer), as: UTF8.self)

        XCTAssertFalse(text.contains("storedNodes"), "an unchanged deployment must not gain a node list")
        XCTAssertFalse(text.contains("placement"))
        XCTAssertTrue(text.contains("\"topology\" : \"vpsRelayWithHomeBackend\""),
                      "the shape the server was installed with is still written down")
        XCTAssertTrue(text.contains("\"vps\" : \"ssh-ed25519 VPS\""),
                      "the slot strings stay in the format, or an older build cannot read this back")

        let again = try DeploymentTransferService.decode(Data(text.utf8))
        XCTAssertEqual(again.deployment, transfer.deployment)
        XCTAssertEqual(again.hostKeyPins, transfer.hostKeyPins)
        XCTAssertEqual(again.installUsers, transfer.installUsers)
    }

    func testABundleWithAThirdMachineRoundTrips() throws {
        var deployment = pair()
        let extra = DeploymentNode(id: UUID(), name: "Second worker",
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: deployment.ingressNode?.id)
        deployment.storedNodes = deployment.derivedNodes + [extra]
        var placement = ServicePlacement()
        placement[.mailcow] = extra.id
        deployment.placement = placement

        let transfer = DeploymentTransfer(
            deployment: deployment,
            sshIdentitySeed: nil,
            dashboardPassword: "entry-pw",
            wireGuardSeeds: [:],
            hostKeyPins: ["vps": "ssh-ed25519 VPS",
                          "home": "ssh-ed25519 HOME",
                          extra.id.uuidString: "ssh-ed25519 THIRD"],
            reports: [],
            installUsers: ["vps": "root", extra.id.uuidString: "worker"],
            dashboardPasswords: ["vps": "entry-pw", extra.id.uuidString: "third-pw"])

        let decoded = try DeploymentTransferService.decode(
            try DeploymentTransferService.encode(transfer))

        XCTAssertEqual(decoded.deployment.nodes.count, 3)
        XCTAssertEqual(decoded.deployment.host(running: .mailcow), .node(extra.id),
                       "where a service lives has to travel with the server")
        XCTAssertEqual(decoded.hostKeyPins[extra.id.uuidString], "ssh-ed25519 THIRD",
                       "without its pin the copy re-trusts whatever key the third machine shows")
        XCTAssertEqual(decoded.dashboardPasswords?[extra.id.uuidString], "third-pw")
        XCTAssertEqual(decoded.installUsers?[extra.id.uuidString], "worker")
    }
}
