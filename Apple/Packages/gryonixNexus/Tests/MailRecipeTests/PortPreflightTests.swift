import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// The port pre-flight, pinned over the GENERATED artifacts
final class PortPreflightTests: XCTestCase {
    private func input(services: Set<ServiceID>) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .ubuntu)],
            services: services
        )
    }

    private func script(_ services: Set<ServiceID>) throws -> String {
        let bundle = try MailRecipe().generate(from: input(services: services))
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    func testTheTableCarriesTheLoopbackPublishesNotOnlyTheFirewallPorts() throws {
        let table = try portTable(in: script([.adguardHome]))
        XCTAssertEqual(table, [
            "127.0.0.1|8087|tcp|adguardhome|AdGuard Home",
            "127.0.0.1|53|tcp|adguardhome|AdGuard Home",
            "127.0.0.1|53|udp|adguardhome|AdGuard Home"
        ])
    }

    func testTheCheckRunsBeforeThePackagesAndBeforeAnyServiceDirectory() throws {
        let text = try script([.adguardHome])
        let preflight = try XCTUnwrap(text.range(of: "GRYONIXNEXUS_PORTS_IN_USE"))
        for later in ["install -d -m 755 /opt/adguardhome", "docker compose -p adguardhome up -d"] {
            let position = try XCTUnwrap(text.range(of: later), "\(later) is missing from the script")
            XCTAssertTrue(preflight.upperBound < position.lowerBound,
                          "the pre-flight must come before «\(later)»")
        }
    }

    func testAServerWithNoContainersHasNoPreflight() throws {
        XCTAssertFalse(try script([]).contains("GRYONIXNEXUS_PORTS_IN_USE"))
    }

    func testThePortVerificationRunsImmediatelyAfterTheContainersComeUp() throws {
        let text = try script([.adguardHome])
        let up = try XCTUnwrap(text.range(of: "docker compose -p adguardhome up -d"))
        let verify = try XCTUnwrap(text.range(of: "gd_pp_verify adguardhome"),
                                   "the generated script never checks that the ports were published")
        let wait = try XCTUnwrap(text.range(of: "/control/install/get_addresses"),
                                 "the readiness wait moved — this test pins the order around it")
        XCTAssertTrue(up.upperBound < verify.lowerBound)
        XCTAssertTrue(verify.upperBound < wait.lowerBound,
                      "the check must come before the readiness wait, or the run still burns it")
    }

    func testEveryComposeServiceBringsItselfUpInOneStep() throws {
        let context = MailContext(input: try input(services: Set(ServiceRegistry.all.map(\.id))),
                                  renderer: StringTemplateRenderer())
        for service in ServiceRegistry.all {
            guard service.composeFile(context.serviceContext) != nil else { continue }
            let steps = service.setupSteps(context.serviceContext)
            XCTAssertTrue(steps.contains { $0.contains("up -d") },
                          "\(service.displayName) has no step that brings its containers up")
        }
    }

    func testEveryCatalogPortEntryIsUnderstood() throws {
        let context = MailContext(input: try input(services: Set(ServiceRegistry.all.map(\.id))),
                                  renderer: StringTemplateRenderer())
        var sawAny = false
        for service in ServiceRegistry.all {
            guard let compose = service.composeFile(context.serviceContext) else { continue }
            let byShape = compose.composeContents.split(separator: "\n").filter { line -> Bool in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- ") else { return false }
                let entry = trimmed.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let body = entry.split(separator: "/").first.map(String.init) ?? entry
                let fields = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                switch fields.count {
                case 2:
                    return fields.allSatisfy { UInt16($0) != nil }
                case 3:
                    let addressLooksLikeIPv4 = fields[0].split(separator: ".").count == 4
                    return addressLooksLikeIPv4 && fields.dropFirst().allSatisfy { UInt16($0) != nil }
                default:
                    return false
                }
            }.count
            XCTAssertEqual(service.publishedHostPorts(context.serviceContext).count, byShape,
                           "\(service.displayName): the pre-flight does not read all of its published ports")
            sawAny = sawAny || byShape > 0
        }
        XCTAssertTrue(sawAny, "the fixture stopped producing compose bodies with ports at all")
    }

    /// The address half survives generation
    func testTheCheckComparesAddressesAndNotOnlyPortNumbers() throws {
        let text = try script([.adguardHome])
        XCTAssertTrue(text.contains("*\" $1:$2 \"*)"), "the exact-address branch is gone")
        XCTAssertTrue(text.contains("*\" 0.0.0.0:$2 \"*)"), "the wildcard branch is gone")
    }

    private func portTable(in script: String) throws -> [String] {
        let start = try XCTUnwrap(script.range(of: "done <<'EOF_GD_PORTS'\n"))
        let end = try XCTUnwrap(script.range(of: "\nEOF_GD_PORTS", range: start.upperBound..<script.endIndex))
        return script[start.upperBound..<end.lowerBound].split(separator: "\n").map(String.init)
    }
}
