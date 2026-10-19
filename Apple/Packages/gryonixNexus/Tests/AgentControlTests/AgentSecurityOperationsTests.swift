import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct SecurityMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// The Security seam — read-only, agent-only, one unary call
final class AgentSecurityOperationsTests: XCTestCase {
    private func payload(_ build: (inout Gryonixnexusd_V1_SecurityStatus) -> Void) throws -> Data {
        var status = Gryonixnexusd_V1_SecurityStatus()
        build(&status)
        return try status.serializedBytes()
    }

    func testTheStatusIsMappedFieldForField() async throws {
        let data = try payload { s in
            s.present = true
            s.engineRunning = true
            s.bouncerRunning = true
            s.engineVersion = "v1.8.0"
            s.alerts24H = 49
            s.localBans = 3
            s.communityBlocklistIps = 15_737
            s.packetsDropped = 21_029
            s.topScenarios = [
                { var x = Gryonixnexusd_V1_SecurityScenario(); x.name = "crowdsecurity/ssh-bf"; x.count = 37; return x }(),
                { var x = Gryonixnexusd_V1_SecurityScenario(); x.name = "crowdsecurity/ssh-slow-bf"; x.count = 11; return x }(),
            ]
            s.recentBans = [{
                var b = Gryonixnexusd_V1_SecurityBan()
                b.ip = "193.233.199.37"; b.country = "RU"
                b.scenario = "crowdsecurity/ssh-slow-bf"; b.at = "2026-09-01T16:25:37Z"
                return b
            }()]
        }
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Security/GetSecurityStatus")
                return data
            })))

        let status = try await ops.status()
        XCTAssertTrue(status.isPresent)
        XCTAssertTrue(status.isHealthy)
        XCTAssertEqual(status.engineVersion, "v1.8.0")
        XCTAssertEqual(status.alertsLast24h, 49)
        XCTAssertEqual(status.localBans, 3)
        XCTAssertEqual(status.communityBlocklistIPs, 15_737)
        XCTAssertEqual(status.packetsDropped, 21_029)
        XCTAssertEqual(status.topScenarios.map(\.name),
                       ["crowdsecurity/ssh-bf", "crowdsecurity/ssh-slow-bf"])
        XCTAssertEqual(status.topScenarios.first?.count, 37)
        XCTAssertEqual(status.recentBans.count, 1)
        XCTAssertEqual(status.recentBans.first?.ip, "193.233.199.37")
        XCTAssertEqual(status.recentBans.first?.country, "RU")
        XCTAssertNotNil(status.recentBans.first?.date)
    }

    func testAHostWithoutCrowdSecMapsToNotPresent() async throws {
        let data = try payload { $0.present = false }
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { _, _ in data })))

        let status = try await ops.status()
        XCTAssertFalse(status.isPresent)
        XCTAssertFalse(status.isHealthy)
        XCTAssertTrue(status.recentBans.isEmpty)
    }

    // MARK: - The SSH password switch

    private func access(_ build: (inout Gryonixnexusd_V1_SshPasswordState) -> Void) throws -> Data {
        var state = Gryonixnexusd_V1_SshPasswordState()
        build(&state)
        return try state.serializedBytes()
    }

    func testTheSSHPasswordStateIsMappedFieldForField() async throws {
        let data = try access { s in
            s.passwordLoginOpen = true
            s.known = true
            s.appKeyPresent = true
            s.dropInPresent = false
            s.sshdPresent = true
            s.loginUser = "gryonixnexus"
        }
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Security/GetSshPasswordState")
                return data
            })))

        let state = try await ops.sshPasswordAccess(loginUser: "gryonixnexus", appPublicKey: "ssh-ed25519 AAAA x")
        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.isClosed)
        XCTAssertTrue(state.canClose)
        XCTAssertFalse(state.isOutranked)
        XCTAssertEqual(state.loginUser, "gryonixnexus")
    }

    func testNoProvenKeyMeansTheCloseIsNotOffered() async throws {
        let data = try access { s in
            s.passwordLoginOpen = true
            s.known = true
            s.appKeyPresent = false
            s.sshdPresent = true
        }
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { _, _ in data })))

        let state = try await ops.sshPasswordAccess(loginUser: "admin", appPublicKey: "ssh-ed25519 AAAA x")
        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.canClose, "the switch would lock the app out of this host")
    }

    func testAnUnknownReadingIsNeitherOpenNorClosed() async throws {
        let data = try access { s in
            s.known = false
            s.detail = "this build can only reach sshd through systemd-run, and this host has none"
        }
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { _, _ in data })))

        let state = try await ops.sshPasswordAccess(loginUser: "root", appPublicKey: "k")
        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.isClosed)
        XCTAssertFalse(state.canClose)
        XCTAssertFalse(state.detail.isEmpty)
    }

    func testADropInThatIsOutrankedIsCalledOut() async throws {
        let data = try access { s in
            s.passwordLoginOpen = true
            s.known = true
            s.dropInPresent = true
            s.appKeyPresent = true
            s.sshdPresent = true
        }
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { _, _ in data })))

        let state = try await ops.sshPasswordAccess(loginUser: "root", appPublicKey: "k")
        XCTAssertTrue(state.isOutranked)
    }

    func testARefusedCloseAnswersWithTheStateTheHostIsActuallyIn() async throws {
        let data = try access { s in
            s.passwordLoginOpen = true
            s.known = true
            s.appKeyPresent = false
            s.sshdPresent = true
            s.detail = "leaving SSH password login ON: no login key is present for 'admin'"
        }
        var sentPath = ""
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { path, _ in
                sentPath = path
                return data
            })))

        let state = try await ops.setSSHPasswordLogin(open: false, loginUser: "admin", appPublicKey: "k")
        XCTAssertEqual(sentPath, "/gryonixnexusd.v1.Security/SetSshPasswordLogin")
        XCTAssertTrue(state.isOpen, "a refusal was rendered as a closed door")
        XCTAssertTrue(state.detail.contains("no login key"))
    }

    func testTheUnknownAccessClaimsNothing() {
        XCTAssertFalse(SSHPasswordAccess.unknown.isOpen)
        XCTAssertFalse(SSHPasswordAccess.unknown.isClosed)
        XCTAssertFalse(SSHPasswordAccess.unknown.canClose)
        XCTAssertFalse(SSHPasswordAccess.unknown.isOutranked)
    }

    // MARK: - Bans and the allowlist

    func testTheDecisionListIsMappedFieldForField() async throws {
        var answer = Gryonixnexusd_V1_SecurityDecisions()
        answer.present = true
        answer.communityCount = 17_707
        answer.sshClientIps = ["198.51.100.9", "198.51.100.4"]
        answer.decisions = [{
            var d = Gryonixnexusd_V1_SecurityDecision()
            d.id = "270036"; d.scope = "Ip"; d.value = "198.51.100.9"
            d.action = "ban"; d.reason = "crowdsecurity/ssh-slow-bf"
            d.country = "DE"; d.asName = "58243 TELE AG"
            d.source = "crowdsec"; d.expiresIn = "3h6m42s"; d.events = 11
            return d
        }()]
        let data = try answer.serializedData()
        var sentPath = ""
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { path, _ in
                sentPath = path
                return data
            })))

        let lists = try await ops.decisions()
        XCTAssertEqual(sentPath, "/gryonixnexusd.v1.Security/GetSecurityDecisions")
        XCTAssertTrue(lists.isPresent)
        XCTAssertEqual(lists.communityCount, 17_707)
        XCTAssertEqual(lists.sshClientIPs, ["198.51.100.9", "198.51.100.4"])
        let decision = try XCTUnwrap(lists.decisions.first)
        XCTAssertEqual(decision.decisionID, "270036")
        XCTAssertEqual(decision.value, "198.51.100.9")
        XCTAssertEqual(decision.country, "DE")
        XCTAssertEqual(decision.asName, "58243 TELE AG")
        XCTAssertEqual(decision.events, 11)
        XCTAssertEqual(decision.expiresIn, "3h6m42s")
        XCTAssertFalse(decision.isManual, "the engine decided this one, not a person")
        XCTAssertEqual(decision.readableReason, "SSH slow brute force")
    }

    func testAHandMadeBanIsToldApart() async throws {
        var answer = Gryonixnexusd_V1_SecurityDecisions()
        answer.present = true
        answer.decisions = [{
            var d = Gryonixnexusd_V1_SecurityDecision()
            d.id = "1"; d.value = "203.0.113.9"; d.source = "cscli"
            d.reason = "gryonixnexus: added by hand"
            return d
        }()]
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { _, _ in try answer.serializedData() })))
        let lists = try await ops.decisions()
        let decision = try XCTUnwrap(lists.decisions.first)
        XCTAssertTrue(decision.isManual)
        XCTAssertEqual(decision.readableReason, "gryonixnexus: added by hand")
    }

    func testLiftingCarriesTheIdWhenThereIsOne() async throws {
        var answer = Gryonixnexusd_V1_SecurityDecisions()
        answer.present = true
        let data = try answer.serializedData()
        var sent = Gryonixnexusd_V1_SetSecurityDecisionRequest()
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Security/SetSecurityDecision")
                sent = try Gryonixnexusd_V1_SetSecurityDecisionRequest(serializedData: request)
                return data
            })))

        _ = try await ops.setBan(false, value: "198.51.100.9", decisionID: "270036")
        XCTAssertFalse(sent.banned)
        XCTAssertEqual(sent.id, "270036")
        XCTAssertEqual(sent.value, "198.51.100.9")

        _ = try await ops.setBan(true, value: "203.0.113.0/24", duration: 7200, reason: "scanning")
        XCTAssertTrue(sent.banned)
        XCTAssertTrue(sent.id.isEmpty, "a new ban has no decision to name")
        XCTAssertEqual(sent.durationSeconds, 7200)
        XCTAssertEqual(sent.reason, "scanning")
    }

    func testAnAllowlistTheHostCannotKeepIsReportedAsUnsupported() async throws {
        var answer = Gryonixnexusd_V1_SecurityAllowlist()
        answer.present = true
        answer.supported = false
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { _, _ in try answer.serializedData() })))
        let list = try await ops.allowlist()
        XCTAssertTrue(list.isPresent)
        XCTAssertFalse(list.isSupported)
        XCTAssertTrue(list.entries.isEmpty)
    }

    func testTheAllowlistIsMappedAndAsksWithTheRightVerb() async throws {
        var answer = Gryonixnexusd_V1_SecurityAllowlist()
        answer.present = true
        answer.supported = true
        answer.name = "gryonixnexus"
        answer.sshClientIps = ["198.51.100.9"]
        answer.entries = [{
            var e = Gryonixnexusd_V1_SecurityAllowlistEntry()
            e.value = "198.51.100.9"; e.comment = "office"; e.expiresIn = ""
            return e
        }()]
        let data = try answer.serializedData()
        var sent = Gryonixnexusd_V1_SetSecurityAllowlistRequest()
        var sentPath = ""
        let ops = AgentSecurityOperations(client: AgentClient(transport: SecurityMockTransport(
            onUnary: { path, request in
                sentPath = path
                sent = try Gryonixnexusd_V1_SetSecurityAllowlistRequest(serializedData: request)
                return data
            })))

        let list = try await ops.setAllowed(true, value: "198.51.100.9", comment: "office")
        XCTAssertEqual(sentPath, "/gryonixnexusd.v1.Security/SetSecurityAllowlist")
        XCTAssertTrue(sent.allowed)
        XCTAssertEqual(sent.value, "198.51.100.9")
        XCTAssertEqual(sent.durationSeconds, 0, "an office address is protected until somebody says otherwise")
        XCTAssertTrue(list.allows("198.51.100.9"))
        XCTAssertFalse(list.allows("198.51.100.4"))
        XCTAssertEqual(list.entries.first?.comment, "office")
        XCTAssertTrue(list.entries.first?.expiresIn.isEmpty == true)
    }

    func testTheUnknownListsClaimNothing() {
        XCTAssertFalse(HostSecurityDecisions.unknown.isPresent)
        XCTAssertTrue(HostSecurityDecisions.unknown.decisions.isEmpty)
        XCTAssertFalse(HostSecurityAllowlist.unknown.isSupported)
        XCTAssertFalse(HostSecurityAllowlist.unknown.allows("203.0.113.9"))
    }

    func testScenarioNamesAreMadeReadableWithASafeFallback() {
        XCTAssertEqual(
            HostSecurityStatus.Scenario(name: "crowdsecurity/ssh-bf", count: 1).readableName,
            "SSH brute force")
        XCTAssertEqual(
            HostSecurityStatus.Scenario(name: "acme/some-new-thing", count: 1).readableName,
            "Some New Thing")
    }
}
