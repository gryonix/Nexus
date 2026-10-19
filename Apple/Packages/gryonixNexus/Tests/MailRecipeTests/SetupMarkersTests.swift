import XCTest
import gryonixNexusCore
@testable import MailRecipe

private final class MarkersFixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        WireGuardKeyPair(privateKey: "TEST-PRIVATE-KEY=", publicKey: "TEST-PUBLIC-KEY=")
    }
}

final class SetupMarkersTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFakeFake gryonixnexus-app"

    private func generate(_ input: MailRecipeInput) throws -> [Artifact] {
        try MailRecipe(keyProvider: MarkersFixedKeyProvider())
            .generate(from: input)
            .artifacts.filter { $0.kind == .shellScript }
    }

    private func inputA(withAccess: Bool = false) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [
                ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)
            ],
            dashboardAccess: withAccess
                ? DashboardAccessInput(sshUser: "admin", appPublicKey: appKey)
                : nil
        )
    }

    private func inputB(withAccess: Bool = false) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            dashboardAccess: withAccess
                ? DashboardAccessInput(sshUser: "admin", appPublicKey: appKey)
                : nil
        )
    }

    private func steps(in script: String) throws -> [(Int, Int)] {
        let pattern = #"^echo "GRYONIXNEXUS_STEP (\d+)/(\d+)"$"#
        let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        let range = NSRange(script.startIndex..., in: script)
        return regex.matches(in: script, range: range).map { match in
            let index = Int((script as NSString).substring(with: match.range(at: 1)))!
            let total = Int((script as NSString).substring(with: match.range(at: 2)))!
            return (index, total)
        }
    }

    // MARK: - Marker structure

    func testEveryScriptCarriesSequentialStepMarkers() throws {
        for input in [try inputA(), try inputB(), try inputA(withAccess: true), try inputB(withAccess: true)] {
            for script in try generate(input) {
                let markers = try steps(in: script.contents)
                XCTAssertFalse(markers.isEmpty, "\(script.fileName): no step markers")
                let total = markers[0].1
                XCTAssertEqual(markers.map(\.0), Array(1...markers.count),
                               "\(script.fileName): indices must be sequential from 1")
                XCTAssertTrue(markers.allSatisfy { $0.1 == total },
                              "\(script.fileName): all markers share one total")
                XCTAssertEqual(markers.count, total,
                               "\(script.fileName): the last step must reach total")
            }
        }
    }

    func testHeaderStaysFirstAndDoneStaysLast() throws {
        for script in try generate(try inputB(withAccess: true)) {
            let text = script.contents
            XCTAssertTrue(text.hasPrefix("#!/usr/bin/env bash"), "\(script.fileName): shebang first")
            XCTAssertEqual(text.components(separatedBy: "\n").last, "echo \"GRYONIXNEXUS_DONE\"",
                           "\(script.fileName): DONE is the very last line")
        }
    }

    func testReportIsWrappedInMarkers() throws {
        for script in try generate(try inputB()) {
            let text = script.contents
            let begin = try XCTUnwrap(text.range(of: "echo \"GRYONIXNEXUS_REPORT_BEGIN\""), script.fileName)
            let end = try XCTUnwrap(text.range(of: "echo \"GRYONIXNEXUS_REPORT_END\""), script.fileName)
            XCTAssertLessThan(begin.lowerBound, end.lowerBound, "\(script.fileName): BEGIN before END")
        }
    }

    func testReportDisablesErrexitAndRestoresIt() throws {
        for script in try generate(try inputB(withAccess: true)) + generate(try inputA(withAccess: true)) {
            let text = script.contents
            let begin = try XCTUnwrap(text.range(of: "echo \"GRYONIXNEXUS_REPORT_BEGIN\""), script.fileName)
            let end = try XCTUnwrap(text.range(of: "echo \"GRYONIXNEXUS_REPORT_END\""), script.fileName)
            let disable = try XCTUnwrap(text.range(of: "set +e"), script.fileName)
            let restore = try XCTUnwrap(text.range(of: "set -e\n", options: [], range: begin.upperBound..<text.endIndex),
                                        "\(script.fileName): errexit restored after the report")
            XCTAssertLessThan(begin.lowerBound, disable.lowerBound,
                              "\(script.fileName): errexit disabled after REPORT_BEGIN")
            XCTAssertLessThan(disable.lowerBound, restore.lowerBound,
                              "\(script.fileName): errexit disabled before it is restored")
            XCTAssertLessThan(restore.lowerBound, end.lowerBound,
                              "\(script.fileName): errexit restored before REPORT_END")
        }
    }

    func testReportIsLeftOnTheServerForTheControlUser() throws {
        XCTAssertEqual(SetupMarkers.reportFilePath, "/var/lib/gryonixnexus/install-report.txt")
        for script in try generate(try inputB(withAccess: true)) + generate(try inputA(withAccess: true)) {
            let text = script.contents
            let end = try XCTUnwrap(text.range(of: "echo \"GRYONIXNEXUS_REPORT_END\""), script.fileName)
            let copy = try XCTUnwrap(
                text.range(of: "cp \"$GD_REPORT_TMP\" /var/lib/gryonixnexus/install-report.txt",
                           options: [], range: end.upperBound..<text.endIndex),
                "\(script.fileName): the report is kept after it is printed")
            XCTAssertTrue(text[copy.upperBound...].contains("chmod 600 /var/lib/gryonixnexus/install-report.txt"),
                          "\(script.fileName): the copy is private")
            XCTAssertTrue(text[copy.upperBound...].contains("chown 'admin' /var/lib/gryonixnexus/install-report.txt"),
                          "\(script.fileName): the control user can read its own report")
        }
    }

    func testReportCopyIsRootOnlyWithoutDashboardAccess() throws {
        for script in try generate(try inputA(withAccess: false)) {
            XCTAssertTrue(script.contents.contains("cp \"$GD_REPORT_TMP\" /var/lib/gryonixnexus/install-report.txt"),
                          "\(script.fileName): still kept for a manual read")
            XCTAssertFalse(script.contents.contains("chown"),
                           "\(script.fileName): no control user exists to hand it to")
        }
    }

    func testDNSCheckFailureMarkerIsPinnedForTheApp() throws {
        XCTAssertEqual(SetupMarkers.dnsCheckFailed, "GRYONIXNEXUS_DNS_CHECK_FAILED")
        let scripts = try (generate(try inputA()) + generate(try inputB()))
            .filter { $0.contents.contains("GRYONIXNEXUS_SKIP_DNS_CHECK") }
        XCTAssertFalse(scripts.isEmpty, "the mail entry scripts carry the DNS check")
        for script in scripts {
            let text = script.contents
            let marker = try XCTUnwrap(text.range(of: "echo \"GRYONIXNEXUS_DNS_CHECK_FAILED\""),
                                       "\(script.fileName): marker before the DNS-check fail")
            let fail = try XCTUnwrap(text.range(of: "fail \"", range: marker.upperBound..<text.endIndex),
                                     "\(script.fileName): the localized failure follows the marker")
            XCTAssertLessThan(marker.lowerBound, fail.lowerBound)
        }
    }

    // MARK: - Install-key revocation

    func testWithAccessRootInstallKeyIsRevokedAfterReport() throws {
        for script in try generate(try inputB(withAccess: true)) + generate(try inputA(withAccess: true)) {
            let text = script.contents
            let reportEnd = try XCTUnwrap(text.range(of: "echo \"GRYONIXNEXUS_REPORT_END\""), script.fileName)
            let revoke = try XCTUnwrap(text.range(of: "revoke_key_for root"), script.fileName)
            XCTAssertLessThan(reportEnd.lowerBound, revoke.lowerBound,
                              "\(script.fileName): revoke runs after the report so a failed report keeps root access for retry")
            XCTAssertTrue(text.contains("grep -vxF \"$APP_KEY\""),
                          "\(script.fileName): only the app's exact key line is removed")
        }
    }

    func testWithAccessNonRootInstallKeyIsRevokedToo() throws {
        for script in try generate(try inputB(withAccess: true)) + generate(try inputA(withAccess: true)) {
            let text = script.contents
            XCTAssertTrue(text.contains("revoke_key_for \"$SUDO_USER\""),
                          "\(script.fileName): the sudo -n install account is revoked as well")
            XCTAssertTrue(text.contains("if [ \"$1\" = \"$CONTROL_USER\" ]; then return 0; fi"),
                          "\(script.fileName): the control user keeps the key the app connects with")
        }
    }

    func testWithoutAccessNothingTouchesRootKeys() throws {
        for input in [try inputA(), try inputB()] {
            for script in try generate(input) {
                XCTAssertFalse(script.contents.contains("revoke_key_for"),
                               "\(script.fileName): no revoke section without dashboard access")
                XCTAssertFalse(script.contents.contains("/root/.ssh"),
                               "\(script.fileName): no revoke section without dashboard access")
            }
        }
    }
}
