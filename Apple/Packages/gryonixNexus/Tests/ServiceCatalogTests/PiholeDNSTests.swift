import XCTest
@testable import ServiceCatalog

final class PiholeDNSTests: XCTestCase {
    /// Blocklist downloads resolve through the upstreams, not the router
    func testTheContainerResolvesThroughItsUpstreams() throws {
        let context = ServiceContext(domain: "example.com", sshUser: "admin", installedServices: [.pihole])
        let compose = try XCTUnwrap(PiholeService().composeFile(context)).composeContents
        XCTAssertTrue(compose.contains("restart: unless-stopped\n    # Blocklist downloads resolve here, not at the router\n"
                                       + "    dns:\n      - 1.1.1.1\n      - 1.0.0.1\n    environment:"))
        XCTAssertEqual(PiholeService.containerDNS("127.0.0.1#5335"), "")
        XCTAssertEqual(PiholeService.containerDNS("9.9.9.9; 127.0.0.1#5335"),
                       "\n    # Blocklist downloads resolve here, not at the router\n    dns:\n      - 9.9.9.9")
    }
}
