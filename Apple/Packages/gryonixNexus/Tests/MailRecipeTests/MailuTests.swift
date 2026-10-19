import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Mailu, pinned over the GENERATED artifacts
final class MailuTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.mailu],
                       aliases: [String] = []) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            additionalDomains: try aliases.map { try Domain($0) },
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .ubuntu)],
            dashboardAccess: DashboardAccessInput(
                sshUser: "admin",
                appPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"),
            services: services
        )
    }

    private func script(_ input: MailRecipeInput) throws -> String {
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    private func frontPortMappings(_ script: String) throws -> [String] {
        guard let frontRange = script.range(of: "\n  front:\n") else {
            XCTFail("missing the generated Mailu front service")
            return []
        }
        let afterFront = script[frontRange.upperBound...]
        guard let portsRange = afterFront.range(of: "ports:\n") else {
            XCTFail("front service has no ports: block")
            return []
        }
        var mappings: [String] = []
        for line in afterFront[portsRange.upperBound...].split(separator: "\n",
                                                                omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            guard trimmed.hasPrefix("-") else { break }
            guard let firstQuote = trimmed.firstIndex(of: "\""),
                  let lastQuote = trimmed.lastIndex(of: "\""), firstQuote != lastQuote else { continue }
            mappings.append(String(trimmed[trimmed.index(after: firstQuote)..<lastQuote]))
        }
        return mappings
    }

    private func hostBind(_ mapping: String) -> (port: Int, loopbackOnly: Bool)? {
        let parts = mapping.split(separator: ":").map(String.init)
        switch parts.count {
        case 2:
            return Int(parts[0]).map { ($0, false) }
        case 3:
            return Int(parts[1]).map { ($0, parts[0] == "127.0.0.1") }
        default:
            return nil
        }
    }

    func testPublicPortsInComposeMatchFirewallPortsExactly() throws {
        let script = try script(input())
        let mappings = try frontPortMappings(script)
        XCTAssertFalse(mappings.isEmpty, "the ports: block parsed empty — the parser drifted from the generator")

        let publicPorts = Set(mappings.compactMap(hostBind).filter { !$0.loopbackOnly }.map(\.port))

        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        let declared = Set(MailuService().firewallPorts(context)
            .filter { $0.proto == .tcp }
            .map(\.port))

        XCTAssertEqual(publicPorts, declared,
                       "the front container's public binds must match firewallPorts exactly — "
                       + "otherwise the firewall/DNAT rules and what docker actually publishes disagree")
    }

    func testTheStartTLSPairIsNeverPublished() throws {
        let script = try script(input())
        let mappings = try frontPortMappings(script)
        for mapping in mappings {
            XCTAssertFalse(mapping.hasSuffix(":143") || mapping.contains(":143:"),
                           "port 143 must not be published: \(mapping)")
            XCTAssertFalse(mapping.hasSuffix(":587") || mapping.contains(":587:"),
                           "port 587 must not be published: \(mapping)")
        }
    }

    func testTheWebUIStaysOnLoopback() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("\"127.0.0.1:\(MailuService.webUIPort):80\""),
                      "the web UI upstream must stay bound to loopback")
    }

    func testNoMailuAdminExecRunsAsRoot() throws {
        let script = try script(input())
        let expected = "exec -T -u \(MailuService.adminRunAsUser) \(MailuService.adminService)"
        var found = 0
        for line in script.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.contains("docker compose -p \(MailuService.composeProject)"),
                  line.contains(" exec ") else { continue }
            found += 1
            XCTAssertTrue(line.contains(expected),
                          "a Mailu admin exec that is not pinned to \(MailuService.adminRunAsUser): \(line)")
        }
        XCTAssertEqual(found, 3, "expected three admin exec call sites in the generated script")
    }
}
