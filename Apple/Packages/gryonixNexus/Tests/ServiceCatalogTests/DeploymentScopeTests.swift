import XCTest
@testable import ServiceCatalog

final class DeploymentScopeTests: XCTestCase {
    func testOnlyTheScopesWithInboundPortsAskACMEForCertificates() {
        XCTAssertFalse(DeploymentScope.publicInternet.usesInternalTLS)
        XCTAssertFalse(DeploymentScope.dynamicDNS.usesInternalTLS,
                       "a moving address is still a reachable one — ACME works there")
        XCTAssertTrue(DeploymentScope.localOnly.usesInternalTLS)
        XCTAssertTrue(DeploymentScope.cloudflareTunnel.usesInternalTLS)
        XCTAssertTrue(DeploymentScope.meshOnly.usesInternalTLS)
    }

    func testOnlyTheScopesWithInboundPortsCarryMailAndVPN() {
        for scope in [DeploymentScope.publicInternet, .dynamicDNS] {
            XCTAssertTrue(scope.carriesNonWebServices, "\(scope.rawValue)")
        }
        for scope in [DeploymentScope.localOnly, .cloudflareTunnel, .meshOnly] {
            XCTAssertFalse(scope.carriesNonWebServices, "\(scope.rawValue)")
        }
    }

    /// The records the wizard asks somebody to paste in
    func testAddressRecordsArePublishedOnlyWhereThereIsAnAddressToPublish() {
        XCTAssertTrue(DeploymentScope.publicInternet.publishesAddressRecords)
        XCTAssertTrue(DeploymentScope.dynamicDNS.publishesAddressRecords)
        XCTAssertFalse(DeploymentScope.localOnly.publishesAddressRecords)
        XCTAssertFalse(DeploymentScope.cloudflareTunnel.publishesAddressRecords)
        XCTAssertFalse(DeploymentScope.meshOnly.publishesAddressRecords)
    }

    func testTheTwoNewScopesAreTheOnlyOnesThatClaimTheirOwnBehaviour() {
        XCTAssertEqual(DeploymentScope.allCases.filter(\.maintainsItsOwnDNSRecords), [.dynamicDNS])
        XCTAssertEqual(DeploymentScope.allCases.filter(\.requiresMesh), [.meshOnly])
    }

    func testRawValuesAreTheStoredFormatAndDoNotMove() {
        XCTAssertEqual(DeploymentScope.publicInternet.rawValue, "publicInternet")
        XCTAssertEqual(DeploymentScope.localOnly.rawValue, "localOnly")
        XCTAssertEqual(DeploymentScope.cloudflareTunnel.rawValue, "cloudflareTunnel")
        XCTAssertEqual(DeploymentScope.dynamicDNS.rawValue, "dynamicDNS")
        XCTAssertEqual(DeploymentScope.meshOnly.rawValue, "meshOnly")
        XCTAssertEqual(DeploymentScope.tailscaleOnly.rawValue, "tailscaleOnly")
    }

    func testTailscaleOnlyBehavesLikeAnOutboundOnlyScope() {
        let scope = DeploymentScope.tailscaleOnly
        XCTAssertTrue(scope.usesInternalTLS)
        XCTAssertFalse(scope.carriesNonWebServices)
        XCTAssertFalse(scope.publishesAddressRecords)
        XCTAssertFalse(scope.requiresMesh, "there is no control server of ours to install")
        XCTAssertEqual(DeploymentScope.allCases.filter(\.joinsTailscale), [.tailscaleOnly])
    }
}

final class ImpliedServiceTests: XCTestCase {
    /// The panel is implied by any protocol; it owns vpn.<domain>
    func testAnyVPNProtocolBringsThePanel() {
        let expanded = ServiceRegistry.expanded([.wireguardVPN], scope: .publicInternet, modelBackend: .here)
        XCTAssertTrue(expanded.contains(.vpnPanel))
    }

    func testATunnelAlwaysBringsItsConnector() {
        XCTAssertTrue(ServiceRegistry.expanded([.vaultwarden], scope: .cloudflareTunnel, modelBackend: .here)
            .contains(.cloudflared))
        XCTAssertFalse(ServiceRegistry.expanded([.vaultwarden], scope: .publicInternet, modelBackend: .here)
            .contains(.cloudflared))
    }

    func testMeshOnlyBringsTheControlServerAndItsNode() {
        let expanded = ServiceRegistry.expanded([.vaultwarden], scope: .meshOnly, modelBackend: .here)
        XCTAssertTrue(expanded.contains(.headscale))
        XCTAssertTrue(expanded.contains(.tailscaleNode),
                      "a control server that never joined its own mesh has no address")
    }

    func testTailscaleOnlyBringsTheNodeButNoControlServer() {
        let expanded = ServiceRegistry.expanded([.vaultwarden], scope: .tailscaleOnly, modelBackend: .here)
        XCTAssertTrue(expanded.contains(.tailscaleNode))
        XCTAssertFalse(expanded.contains(.headscale),
                       "a Headscale behind a router cannot be reached from outside")
    }

    func testTheControlServerAlwaysImpliesItsNode() {
        XCTAssertTrue(ServiceRegistry.expanded([.headscale], scope: .publicInternet, modelBackend: .here)
            .contains(.tailscaleNode))
    }

    func testAPlainSelectionIsUnchanged() {
        let selection: Set<ServiceID> = [.vaultwarden, .nextcloud]
        XCTAssertEqual(ServiceRegistry.expanded(selection, scope: .publicInternet, modelBackend: .here), selection)
    }
}
