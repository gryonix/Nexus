import XCTest

@testable import gryonixNexus

@MainActor
final class DemoAddressTests: XCTestCase {
    func testOwnAddressesBecomeDocumentationOnes() {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .publicInternet)
        model.domain = "mine.example.org"
        model.publicIP = "198.51.100.7"
        model.additionalDomains = ["second.example.org"]
        model.vpnHostname = "vpn.example.org"
        model.reverseDNSHostname = "mail.example.org"

        model.useDemoAddressesIfLocked()

        XCTAssertEqual(model.domain, ServiceConfigViewModel.demoDomain)
        XCTAssertEqual(model.publicIP, ServiceConfigViewModel.demoPublicIP)
        XCTAssertTrue(model.additionalDomains.isEmpty)
        XCTAssertTrue(model.vpnHostname.isEmpty)
        XCTAssertTrue(model.reverseDNSHostname.isEmpty)
    }

    func testALocalOnlyCopyUsesOneLocalAddressForBoth() {
        let model = ServiceConfigViewModel(topology: .singleHost, initialScope: .localOnly)
        model.useDemoAddressesIfLocked()

        XCTAssertEqual(model.publicIP, ServiceConfigViewModel.demoLocalIP)
        XCTAssertEqual(model.domain, model.publicIP)
    }

    func testTheDemoAddressesAreDocumentationRanges() {
        XCTAssertTrue(DemoServer.isDocumentationHost(ServiceConfigViewModel.demoPublicIP))
    }
}
