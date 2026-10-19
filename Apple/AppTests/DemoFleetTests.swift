import AgentControl
import ServerControl
import ServiceCatalog
import AgentClient
import XCTest

@testable import gryonixNexus

final class DemoFleetTests: XCTestCase {
    private let fleet = DemoServer.deployments()

    func testTheFleetCoversEveryFormOfServerTheAppSupports() {
        XCTAssertTrue(fleet.contains { $0.topology == .singleHost && $0.usesAgent },
                      "the agent path owns whole screens (add a service, the log stream, mesh)")
        XCTAssertTrue(fleet.contains { $0.hasHomeHost },
                      "only a two-machine deployment gives the Servers screen and the per-machine bars anything to draw")
        XCTAssertTrue(fleet.contains { $0.scope == .localOnly },
                      "local-only hides the domain section and the VPN — it is a different form, not a setting")
        XCTAssertTrue(fleet.contains { !$0.usesAgent },
                      "without the SSH path the demo never shows the log snapshot or 'managed in the panel'")
    }

    func testOnlyTheFleetCountsAsTheDemo() throws {
        for deployment in fleet {
            XCTAssertTrue(DemoServer.isDemo(deployment), "\(deployment.name)")
        }
        let stranger = Deployment(name: "someone else's",
                                  topology: .singleHost,
                                  entry: HostEndpoint(host: "203.0.113.99", user: "root"))
        XCTAssertFalse(DemoServer.isDemo(stranger))
    }

    func testTheFleetHasNoDuplicateIds() {
        XCTAssertEqual(Set(fleet.map(\.id)).count, fleet.count)
    }

    /// Every machine of every demo server has a character
    func testEveryDemoMachineHasAProfile() throws {
        for deployment in fleet {
            for node in deployment.nodes {
                XCTAssertNotNil(DemoServer.profile(deploymentID: deployment.id, host: node.sshHost),
                                "\(deployment.name) / \(node.sshHost)")
            }
        }
    }

    func testReadingsStayInCharacterHoursIntoTheSession() throws {
        for deployment in fleet {
            for node in deployment.nodes {
                let host = node.sshHost
                let profile = try XCTUnwrap(DemoServer.profile(deploymentID: deployment.id, host: host))
                for tick in [UInt64(1), 12, 720] {
                    let snapshot = DemoHostMetrics.snapshot(deploymentID: deployment.id,
                                                            host: host, tick: tick)
                    let where_ = "\(deployment.name) / \(host) @\(tick)"

                    let cpu = try XCTUnwrap(snapshot.cpuPercent, where_)
                    XCTAssertGreaterThanOrEqual(cpu, (profile.cpuBusy - profile.cpuSwing) * 100 - 2, where_)
                    XCTAssertLessThanOrEqual(cpu, (profile.cpuBusy + profile.cpuSwing) * 100 + 2, where_)

                    let received = try XCTUnwrap(snapshot.netReceivedPerSecond, where_)
                    XCTAssertGreaterThanOrEqual(received, profile.netReceivedPerSecond * 0.65, where_)
                    XCTAssertLessThanOrEqual(received, profile.netReceivedPerSecond * 1.05, where_)

                    let written = try XCTUnwrap(snapshot.diskWrittenPerSecond, where_)
                    XCTAssertGreaterThanOrEqual(written, profile.diskWrittenPerSecond * 0.65, where_)
                    XCTAssertLessThanOrEqual(written, profile.diskWrittenPerSecond * 1.05, where_)
                }
            }
        }
    }

    func testTheMachinesAreDistinguishableFromEachOther() throws {
        let relay = try XCTUnwrap(DemoServer.profile(deploymentID: DemoServer.relayPairID,
                                                      host: .vps))
        let home = try XCTUnwrap(DemoServer.profile(deploymentID: DemoServer.relayPairID,
                                                     host: .home))
        let vault = try XCTUnwrap(DemoServer.profile(deploymentID: DemoServer.localOnlyID,
                                                      host: .vps))
        let lab = try XCTUnwrap(DemoServer.profile(deploymentID: DemoServer.sshOnlyID,
                                                    host: .vps))

        XCTAssertGreaterThan(relay.netReceivedPerSecond, home.diskWrittenPerSecond,
                             "a relay forwards traffic and barely touches its disk")
        XCTAssertGreaterThan(home.cpuBusy, relay.cpuBusy,
                             "the home half runs the services the relay only forwards to")
        XCTAssertGreaterThan(vault.netSentPerSecond, vault.netReceivedPerSecond * 4,
                             "a media box sends far more than it receives")
        XCTAssertGreaterThan(vault.diskUsedFraction, lab.diskUsedFraction,
                             "the fullest disk of the fleet is the one full of photos")
        XCTAssertNil(lab.temperatureCelsius,
                     "a rented VPS reports no sensor, and the card has to survive that")
        XCTAssertNotNil(home.temperatureCelsius,
                        "a machine at home does report one, and the card has to draw it")
    }

    func testHistoryAgreesWithTheCardItSitsUnder() throws {
        for deployment in fleet {
            for node in deployment.nodes {
                let host = node.sshHost
                let profile = try XCTUnwrap(DemoServer.profile(deploymentID: deployment.id, host: host))
                let points = DemoHostMetrics.history(deploymentID: deployment.id,
                                                     host: host, bucket: .tenSeconds)
                XCTAssertFalse(points.isEmpty)
                let readings = points.compactMap(\.cpuPercent)
                XCTAssertEqual(readings.count, points.count, "every generated point carries a CPU reading")
                let averageCPU = readings.reduce(0, +) / Double(readings.count)
                XCTAssertEqual(averageCPU, profile.cpuBusy * 100,
                               accuracy: profile.cpuBusy * 100 * 0.6 + 5,
                               "\(deployment.name) / \(host)")
                let last = try XCTUnwrap(points.last)
                XCTAssertEqual(last.diskTotalBytes, profile.diskTotalBytes)
                XCTAssertEqual(Double(last.diskUsedBytes) / Double(last.diskTotalBytes),
                               profile.diskUsedFraction, accuracy: 0.01,
                               "the chart has to end where the card says the disk is now")
                XCTAssertTrue(points.allSatisfy { ($0.netSentPerSecond ?? 0) >= 0 },
                              "a counter cannot run backwards, so its rate cannot be negative")
            }
        }
    }

    // MARK: - The agent-only surfaces

    @available(macOS 15.0, *)
    private func vpnOperations(_ deployment: Deployment) throws -> AgentVPNClientOperations {
        AgentVPNClientOperations(client: try XCTUnwrap(DemoAgent.client(for: deployment)))
    }

    @available(macOS 15.0, *)
    private func meshOperations(_ deployment: Deployment) throws -> AgentMeshOperations {
        AgentMeshOperations(client: try XCTUnwrap(DemoAgent.client(for: deployment)))
    }

    @available(macOS 15.0, *)
    func testEveryDemoServerThatManagesDevicesHasSomeToShow() async throws {
        for deployment in fleet where deployment.usesAgent {
            for id in VPNClientProtocols.installed(in: deployment.services) {
                guard id == .wireguardVPN else { continue }
                let ops = try vpnOperations(deployment)
                let devices = try await ops.list(protocol: id)
                XCTAssertFalse(devices.isEmpty, "\(deployment.name) manages \(id.rawValue) devices")
                XCTAssertTrue(devices.allSatisfy { !$0.name.isEmpty && !$0.detail.isEmpty },
                              "a device with no name or no address reads as a broken listing")
            }
        }
    }

    @available(macOS 15.0, *)
    func testTheMeshDemoShowsTheServerItselfOnline() async throws {
        let host = try XCTUnwrap(fleet.first { $0.services.contains(.headscale) })
        let ops = try meshOperations(host)
        let nodes = try await ops.nodes()
        XCTAssertGreaterThan(nodes.count, 1, "a mesh of one device shows nothing about a mesh")
        let own = try XCTUnwrap(nodes.first)
        XCTAssertTrue(own.isOnline, "the control server has to be in its own network")
        XCTAssertFalse(own.addresses.isEmpty)
        XCTAssertTrue(nodes.contains { !$0.isOnline },
                      "an all-online list never shows what an offline device looks like")
    }

    @available(macOS 15.0, *)
    func testChangingSomethingOnTheAgentSurfacesIsShownInTheNextList() async throws {
        await DemoAgentState.shared.forgetEverything()
        let vpn = try vpnOperations(DemoServer.deployment())
        let mesh = try meshOperations(DemoServer.deployment())

        let before = try await vpn.list(protocol: .wireguardVPN)
        let added = try await vpn.add(protocol: .wireguardVPN, named: "New phone")
        XCTAssertEqual(added.count, before.count + 1)
        XCTAssertTrue(added.contains { $0.name == "New phone" }, "the device just added has to be in the list")
        let listedAgain = try await vpn.list(protocol: .wireguardVPN)
        XCTAssertEqual(listedAgain.count, added.count, "the addition has to survive the next read")

        let removed = try await vpn.remove(protocol: .wireguardVPN, clientID: added[0].id)
        XCTAssertEqual(removed.count, added.count - 1)

        let nodes = try await mesh.nodes()
        let afterRemoval = try await mesh.removeNode(id: "2")
        XCTAssertEqual(afterRemoval.count, nodes.count - 1)
        let afterOwn = try await mesh.removeNode(id: "1")
        XCTAssertEqual(afterOwn.count, afterRemoval.count)

        let published = try await mesh.publishNames(["vault.gryonix.com"], nodeName: "gryonix-com")
        XCTAssertEqual(published.map(\.name), ["vault.gryonix.com"])
    }

    @available(macOS 15.0, *)
    func testAMintedJoinKeyIsVisiblyNotAKey() async throws {
        let mesh = try meshOperations(DemoServer.deployment())
        let key = try await mesh.mintAuthKey(userID: "1", reusable: false, expirationHours: 24)
        XCTAssertTrue(key.key.contains("demo"), "got: \(key.key)")
        XCTAssertTrue(key.key.contains("not-a-key"), "got: \(key.key)")
    }

    @available(macOS 15.0, *)
    func testADeviceConfigurationIsShaped() async throws {
        let vpn = try vpnOperations(DemoServer.deployment())
        let config = try await vpn.configuration(protocol: .wireguardVPN, clientID: "wg-2")
        XCTAssertTrue(config.text.contains("[Interface]"), "got: \(config.text)")
        XCTAssertTrue(config.text.contains("[Peer]"))
        XCTAssertFalse(config.fileName.isEmpty)
        XCTAssertTrue(config.qrIsUseful, "a WireGuard config is small enough to scan")
    }

    @available(macOS 15.0, *)
    func testAddingADeviceToASecondProtocolIsAnswered() async throws {
        let server = try XCTUnwrap(DemoServer.deployments().first { $0.services.contains(.shadowsocks) })
        let vpn = try vpnOperations(server)
        let before = try await vpn.list(protocol: .shadowsocks)
        let after = try await vpn.add(protocol: .shadowsocks, named: "Phone")
        XCTAssertEqual(after.count, before.count + 1)
        XCTAssertTrue(after.contains { $0.name == "Phone" })
    }
}
