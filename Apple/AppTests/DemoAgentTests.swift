import AgentClient
import ServerControl
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
final class DemoAgentTests: XCTestCase {
    private var deployment: Deployment { DemoServer.deployment() }

    override func setUp() async throws {
        try await super.setUp()
        await DemoFleetState.shared.forgetEverything()
        await DemoAgentState.shared.forgetEverything()
    }

    func testARealServerGetsNoDemoAgent() {
        var adopted = Deployment(name: "adopted", topology: .singleHost, domain: "example.com",
                                 entry: HostEndpoint(host: "203.0.113.10", user: "root"))
        adopted.usesAgent = true
        XCTAssertNil(DemoAgent.client(for: adopted))
        XCTAssertNotNil(DemoAgent.client(for: deployment))
    }

    func testTheDemoServerAnswersWithItsOwnAgentAndServices() async throws {
        let client = try XCTUnwrap(DemoAgent.client(for: deployment))

        let state = try await client.getState()

        XCTAssertFalse(state.agentVersion.isEmpty, "the demo agent claims no version")
        XCTAssertEqual(state.host.hostname, deployment.name)
        XCTAssertEqual(Set(state.services.map(\.id)),
                       Set(deployment.installedServices.map(\.id.rawValue)),
                       "the demo agent lists services this server does not carry")
        XCTAssertTrue(state.services.allSatisfy { $0.status == .running })
    }

    func testStoppingAServiceIsRememberedByTheNextRead() async throws {
        let client = try XCTUnwrap(DemoAgent.client(for: deployment))
        let target = try XCTUnwrap(deployment.installedServices.first).id.rawValue

        for try await _ in client.controlService(serviceID: target, action: .stop) {}

        let state = try await client.getState()
        let service = try XCTUnwrap(state.services.first { $0.id == target })
        XCTAssertEqual(service.status, .stopped, "the demo machine forgot the stop")
    }

    func testABackupRunAddsAnArchiveTheListThenCarries() async throws {
        let client = try XCTUnwrap(DemoAgent.client(for: deployment))
        let target = try XCTUnwrap(deployment.installedServices.first).id.rawValue
        let before = try await client.listBackups(serviceID: target).archives.count

        var sawArchive = false
        for try await event in client.runBackup(serviceID: target) {
            if event.hasArchive { sawArchive = true }
        }

        XCTAssertTrue(sawArchive, "the run never named the archive it made")
        let after = try await client.listBackups(serviceID: target).archives
        XCTAssertEqual(after.count, before + 1)
        XCTAssertFalse(after[0].path.isEmpty, "an archive with no path cannot be deleted")
    }

    func testRemovingAServiceTakesItOutOfTheState() async throws {
        let client = try XCTUnwrap(DemoAgent.client(for: deployment))
        let target = try XCTUnwrap(deployment.installedServices.first).id.rawValue

        for try await _ in client.removeService(serviceID: target, purgeData: false, purgeBackups: false) {}

        let state = try await client.getState()
        XCTAssertFalse(state.services.contains { $0.id == target },
                       "a removed service is still listed")
    }

    func testTheSecurityScreenReadsSomethingRatherThanFailing() async throws {
        let client = try XCTUnwrap(DemoAgent.client(for: deployment))

        let status = try await client.getSecurityStatus()
        let ssh = try await client.getSSHPasswordState(loginUser: "server-user", appPublicKey: "k")
        let lockdown = try await client.getLockdown()

        XCTAssertTrue(status.present)
        XCTAssertTrue(ssh.known)
        XCTAssertEqual(lockdown.mode, .off)
    }

    func testClosingPasswordLoginIsRemembered() async throws {
        let client = try XCTUnwrap(DemoAgent.client(for: deployment))

        _ = try await client.setSSHPasswordLogin(open: true, loginUser: "server-user",
                                                 appPublicKey: "k")
        let opened = try await client.getSSHPasswordState(loginUser: "server-user",
                                                          appPublicKey: "k")
        XCTAssertTrue(opened.passwordLoginOpen)

        _ = try await client.setSSHPasswordLogin(open: false, loginUser: "server-user",
                                                 appPublicKey: "k")
        let closed = try await client.getSSHPasswordState(loginUser: "server-user",
                                                          appPublicKey: "k")
        XCTAssertFalse(closed.passwordLoginOpen)
    }

    func testPairedDevicesCanBeAddedAndRevoked() async throws {
        let client = try XCTUnwrap(DemoAgent.client(for: deployment))
        let before = try await client.listDevices().count

        let paired = try await client.pair(code: "123456", devicePublicKey: "ssh-ed25519 AAA",
                                           label: "iPad", deviceUID: "uid")
        let added = try await client.listDevices().count
        XCTAssertEqual(added, before + 1)

        let revoked = try await client.revoke(deviceID: paired.id)
        XCTAssertTrue(revoked)
        let left = try await client.listDevices().count
        XCTAssertEqual(left, before)
    }

    func testAnUnknownCallIsRefusedRatherThanAnsweredWithNothing() async throws {
        let transport = DemoAgentTransport(deployment: deployment)
        do {
            _ = try await transport.unary(path: "/gryonixnexusd.v1.Nowhere/Nothing",
                                          request: Data())
            XCTFail("an unimplemented call answered")
        } catch let error as AgentError {
            guard case .rpc(let code, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(code, "unimplemented")
        }
    }
}
