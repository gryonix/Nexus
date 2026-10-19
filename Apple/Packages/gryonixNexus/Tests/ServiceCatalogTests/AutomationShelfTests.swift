import XCTest
@testable import MailRecipe
@testable import ServiceCatalog

private let base = ServiceContext(domain: "example.com", sshUser: "admin",
                                  installedServices: [.n8n])

final class AutomationShelfTests: XCTestCase {
    // MARK: - The shelf

    func testAutomationIsItsOwnShelfAndTheAIShelfDoesNotImplyIt() {
        XCTAssertEqual(N8NService().category, ServiceCategory.automation)
        XCTAssertNotEqual(ServiceCategory.automation, ServiceCategory.ai)
        XCTAssertTrue(ServiceCategory.selectable.contains(ServiceCategory.automation),
                      "a shelf nobody can pick from is a service nobody can install")

        let ai = ServiceRegistry.expanded([.openWebUI], scope: .publicInternet, modelBackend: .here)
        XCTAssertFalse(ai.contains(.n8n))
        let flows = ServiceRegistry.expanded([.n8n], scope: .publicInternet, modelBackend: .here)
        XCTAssertFalse(flows.contains(.ollama),
                       "a workflow engine is useful with no model at all, so it may not drag one in")
        XCTAssertEqual(flows, [.n8n])
    }

    func testTheShelfExpectsASecondProductAndConflictsWithNothing() {
        XCTAssertEqual(ServiceCategory.automation.selection, .preferOne)
        XCTAssertTrue(N8NService().conflicts.isEmpty,
                      "preferOne is a UI preference, not a port fight")
    }

    // MARK: - The webhooks, which is why the ingress model changed

    func testTheWebhookPathsArePublicAndNothingElseIs() throws {
        let ingress = try XCTUnwrap(N8NService().webIngress(base))
        XCTAssertTrue(ingress.adminGuard, "the editor holds every credential these workflows use")
        XCTAssertEqual(ingress.publicPaths, ["/webhook/*", "/webhook-test/*"])
    }

    /// The test prefix as well as the production one
    func testTheEditorsOwnTestURLIsReachableToo() throws {
        let ingress = try XCTUnwrap(N8NService().webIngress(base))
        XCTAssertTrue(ingress.publicPaths.contains("/webhook-test/*"))
    }

    func testTheGuardSitsInsideTheBranchThatIsNotThePublicOne() {
        let site = ServiceInfraSections.caddySite(
            owner: ServiceID.n8n.rawValue,
            hostname: "flows.example.com",
            upstreamPort: N8NService.webUIPort,
            adminGuard: true,
            publicPaths: N8NService.webhookPaths)

        XCTAssertTrue(site.contains("@gryonixnexus_open path /webhook/* /webhook-test/*"),
                      "the public prefixes are named in a matcher of their own")

        guard let publicBranch = site.range(of: "handle @gryonixnexus_open"),
              let guardImport = site.range(of: "import \(VPNPanelService.adminGuardPath)") else {
            return XCTFail("the site must have both a public branch and a guarded one")
        }
        XCTAssertTrue(publicBranch.lowerBound < guardImport.lowerBound,
                      "the guard must not precede the public branch — at the top of the site it "
                          + "sorts ahead of the path matcher and refuses the webhook")
        // Exactly one guard, in exactly one of the two branches.
        XCTAssertEqual(site.components(separatedBy: "import \(VPNPanelService.adminGuardPath)").count - 1, 1)
    }

    func testSignOnDoesNotReachTheWebhookBranch() {
        let site = ServiceInfraSections.caddySite(
            owner: ServiceID.n8n.rawValue,
            hostname: "flows.example.com",
            upstreamPort: N8NService.webUIPort,
            adminGuard: true, sso: true,
            publicPaths: N8NService.webhookPaths)
        guard let publicBranch = site.range(of: "handle @gryonixnexus_open"),
              let forwardAuth = site.range(of: "forward_auth") else {
            return XCTFail("the site must have both a public branch and a portal check")
        }
        XCTAssertTrue(publicBranch.lowerBound < forwardAuth.lowerBound)
    }

    func testTheSplitAppearsOnlyWhereThereIsSomethingToBeExemptFrom() {
        let plain = ServiceInfraSections.caddySite(owner: "x", hostname: "x.example.com",
                                                   upstreamPort: 8000, adminGuard: true)
        XCTAssertFalse(plain.contains("handle"))

        let unguarded = ServiceInfraSections.caddySite(owner: "x", hostname: "x.example.com",
                                                       upstreamPort: 8000, adminGuard: false,
                                                       publicPaths: ["/webhook/*"])
        XCTAssertFalse(unguarded.contains("handle"),
                       "an unrestricted site has nothing to exempt, so it keeps its one shape")
    }

    // MARK: - What the install actually puts on the host

    func testTheEncryptionKeyIsNotInAnythingTheBackupLeavesBehind() throws {
        let compose = try XCTUnwrap(N8NService().composeFile(base))
        let env = try XCTUnwrap(compose.envTemplate)
        XCTAssertFalse(env.contains("ENCRYPTION"))
        XCTAssertFalse(compose.composeContents.contains("N8N_ENCRYPTION_KEY"))

        let backup = try XCTUnwrap(N8NService().actions(base).backup)
        guard case .wrapperScript(let spec) = backup, case .archive(let plan) = spec.plan else {
            return XCTFail("n8n takes an archive backup")
        }
        XCTAssertEqual(plan.dataPath, "/opt/n8n/data",
                       "the settings directory is where n8n writes the key")
        XCTAssertTrue(plan.encryptsByDefault,
                      "credentials and the key that opens them, in one file")
    }

    func testTheDatabaseIsDumpedRatherThanArchived() throws {
        let backup = try XCTUnwrap(N8NService().actions(base).backup)
        guard case .wrapperScript(let spec) = backup, case .archive(let plan) = spec.plan else {
            return XCTFail("n8n takes an archive backup")
        }
        XCTAssertEqual(plan.databases.map(\.fileName), ["n8n.sql"])
        XCTAssertEqual(plan.databases.map(\.engine), [.postgres])
        XCTAssertFalse(plan.dataPath.hasSuffix("/postgres"))
        XCTAssertTrue(plan.sizePaths.contains("/opt/n8n/postgres"),
                      "the estimate still has to measure it")
    }

    func testThePublicAddressIsToldToIt() throws {
        let compose = try XCTUnwrap(N8NService().composeFile(base)).composeContents
        XCTAssertTrue(compose.contains("N8N_HOST: flows.example.com"))
        XCTAssertTrue(compose.contains(#"WEBHOOK_URL: "https://flows.example.com/""#))
        XCTAssertTrue(compose.contains(#"N8N_EDITOR_BASE_URL: "https://flows.example.com/""#))
    }

    func testTheDataDirectoryBelongsToTheContainersUser() {
        let steps = N8NService().setupSteps(base).joined(separator: "\n")
        XCTAssertTrue(steps.contains("install -d -m 700 -o 1000 -g 1000 /opt/n8n/data"))
        XCTAssertFalse(steps.contains("install -d -m 755 /opt/n8n/postgres"),
                       "the postgres image refuses a data directory it did not make")
    }

    func testTelemetryIsOff() throws {
        let compose = try XCTUnwrap(N8NService().composeFile(base)).composeContents
        XCTAssertTrue(compose.contains(#"N8N_DIAGNOSTICS_ENABLED: "false""#))
    }

    func testTheReportSaysTheWebhooksArePublic() {
        let report = N8NService().reportSteps(base).joined(separator: "\n")
        XCTAssertTrue(report.contains("/webhook/"))
        XCTAssertTrue(report.contains("flows.example.com"))
    }

    func testTheServiceHasAHostnameField() {
        XCTAssertNotNil(ServiceSettings.hostnameSettings[.n8n])
        XCTAssertEqual(N8NService().hostname(base), "flows.example.com")
        var custom = ServiceSettings()
        custom.n8nHostname = "automation.example.com"
        let context = ServiceContext(domain: "example.com", sshUser: "admin", settings: custom)
        XCTAssertEqual(N8NService().hostname(context), "automation.example.com")
    }

    func testDeploymentsStoredBeforeTheShelfKeepDecoding() throws {
        let json = Data(#"{"domain":"example.com"}"#.utf8)
        let settings = try JSONDecoder().decode(ServiceSettings.self, from: json)
        XCTAssertEqual(settings.n8nPath, "/opt/n8n")
        XCTAssertEqual(settings.n8nHostname, "")
    }
}
