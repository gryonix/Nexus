import XCTest
@testable import MailRecipe
import ServiceCatalog

final class PortalPathsTests: XCTestCase {
    func testOnlyMailcowAdminPagesAskForThePortal() throws {
        let site = ServiceInfraSections.caddySite(owner: "mailcow", hostname: "mail.example.com", upstreamPort: 18443,
                                                  adminGuard: true, upstreamHTTPS: true, sso: true)
        if let dump = ProcessInfo.processInfo.environment["GRYONIXNEXUS_SITE_DUMP"] {
            try Data(site.utf8).write(to: URL(fileURLWithPath: dump))
        }
        let parts = site.components(separatedBy: "    handle {")
        XCTAssertEqual(parts.count, 2, site)
        XCTAssertTrue(parts[0].contains("path /admin /admin/* /domainadmin /domainadmin/* /rspamd /rspamd/*"))
        XCTAssertTrue(parts[0].contains("forward_auth"))
        XCTAssertTrue(parts[1].contains("import /etc/caddy/gryonixnexus-admin-guard"), "webmail stays VPN-only")
        XCTAssertFalse(parts[1].contains("forward_auth"), "mailbox users sign in to mailcow, not the portal")
        let other = ServiceInfraSections.caddySite(owner: "nextcloud", hostname: "files.example.com", upstreamPort: 8081,
                                                   adminGuard: true, sso: true)
        XCTAssertFalse(other.contains("handle"))
    }

    func testMailcowSyncPathsAnswerOutsideTheVPN() throws {
        for sso in [false, true] {
            let site = ServiceInfraSections.caddySite(owner: "mailcow", hostname: "mail.example.com", upstreamPort: 18443,
                                                      adminGuard: true, upstreamHTTPS: true, sso: sso,
                                                      publicPaths: MailcowService.syncPaths)
            if let dump = ProcessInfo.processInfo.environment["GRYONIXNEXUS_SYNC_SITE_DUMP"] {
                try Data(site.utf8).write(to: URL(fileURLWithPath: "\(dump)-\(sso ? "sso" : "plain").txt"))
            }
            let parts = site.components(separatedBy: "    handle ")
            XCTAssertEqual(parts.count, sso ? 4 : 3, site)
            XCTAssertTrue(parts[0].contains("@gryonixnexus_open path /SOGo/dav /SOGo/dav/* /.well-known/caldav"), site)
            XCTAssertFalse(parts[1].contains("import"), "calendars and contacts skip the admin guard")
            XCTAssertFalse(parts[1].contains("forward_auth"), "mail apps cannot sign in to the portal")
            XCTAssertTrue(parts.last!.contains("import /etc/caddy/gryonixnexus-admin-guard"), "webmail stays VPN-only")
            XCTAssertFalse(parts.last!.contains("forward_auth"))
            if sso {
                XCTAssertTrue(parts[2].hasPrefix("@gryonixnexus_portal {"), site)
                XCTAssertTrue(parts[2].contains("forward_auth"))
                XCTAssertTrue(parts[2].contains("import /etc/caddy/gryonixnexus-admin-guard"))
            }
        }
    }
}
