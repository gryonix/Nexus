import XCTest
@testable import ServerControl
import ServiceCatalog

final class HomeOnlyTests: XCTestCase {
    private func relay(homeOnly: Set<ServiceID>, noVPN: Set<ServiceID> = [],
                       dnsRemoved: Set<ServiceID> = [], services: Set<ServiceID> = []) -> Deployment {
        Deployment(name: "R", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "server-user"),
                   homeWGAddress: "10.8.0.2", services: services, homeOnlyServices: homeOnly,
                   homeOnlyNoVPN: noVPN, homeOnlyDNSRemoved: dnsRemoved)
    }

    private static let pem = """
    -----BEGIN CERTIFICATE-----
    MIIBmTCCAT+gAwIBAgIUEO3h3YxEzm7G4aIPS8ICwdNhgZUwCgYIKoZIzj0EAwIw
    IjEgMB4GA1UEAwwXRXhhbXBsZSBMb2NhbCBBdXRob3JpdHkwHhcNMjYxMTA3MDkw
    MDE4WhcNMzYxMTA0MDkwMDE4WjAiMSAwHgYDVQQDDBdFeGFtcGxlIExvY2FsIEF1
    dGhvcml0eTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABLuMs44aS+fTSijyZw8g
    NEI5mR20sVJlxlIL1Q3N+/E2t1007H8wP+NVgtXYOtG5pJCzxjWoJ/S08xYLVPJW
    iU6jUzBRMB0GA1UdDgQWBBRJS+5BEHbuyR6JV8VnpqHihpJElzAfBgNVHSMEGDAW
    gBRJS+5BEHbuyR6JV8VnpqHihpJElzAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49
    BAMCA0gAMEUCIDhQzrm3mmhsxiIQvfZDw+mLGzNZmRfAk/SwzP3bQ1PKAiEA4uTq
    FUDW+mWsfhX0Zcm0CvUT574uIK94MIsfYvYMZ8k=
    -----END CERTIFICATE-----
    """

    func testAHomeServerWithAChangingAddressClosesServicesAtHome() {
        var home = Deployment(name: "H", topology: .singleHost, domain: "example.com",
                              entry: HostEndpoint(host: "203.0.113.10", user: "server-user"))
        XCTAssertFalse(home.closesServicesAtHome)
        home.scope = .dynamicDNS
        XCTAssertTrue(home.closesServicesAtHome)
        XCTAssertTrue(relay(homeOnly: []).closesServicesAtHome)
    }

    func testHomeOnlyServicesRoundTrip() throws {
        let decoded = try JSONDecoder().decode(
            Deployment.self, from: JSONEncoder().encode(relay(homeOnly: [.nextcloud])))
        XCTAssertEqual(decoded.homeOnlyServices, [.nextcloud])
    }

    func testEmptyHomeOnlyIsOmitted() throws {
        let json = try String(decoding: JSONEncoder().encode(relay(homeOnly: [])), as: UTF8.self)
        XCTAssertFalse(json.contains("homeOnlyServices"))
    }

    func testNoVPNAndRemovedRecordsRoundTrip() throws {
        let decoded = try JSONDecoder().decode(
            Deployment.self,
            from: JSONEncoder().encode(relay(homeOnly: [.nextcloud], noVPN: [.nextcloud], dnsRemoved: [.nextcloud])))
        XCTAssertEqual(decoded.homeOnlyNoVPN, [.nextcloud])
        XCTAssertEqual(decoded.homeOnlyDNSRemoved, [.nextcloud])
    }

    func testEmptyNoVPNAndRemovedRecordsAreOmitted() throws {
        let json = try String(decoding: JSONEncoder().encode(relay(homeOnly: [.nextcloud])), as: UTF8.self)
        XCTAssertFalse(json.contains("homeOnlyNoVPN"))
        XCTAssertFalse(json.contains("homeOnlyDNSRemoved"))
    }

    func testOnlyHomeOnlyServicesRefuseVPN() {
        let both = relay(homeOnly: [.nextcloud], noVPN: [.nextcloud, .vaultwarden], services: [.nextcloud, .vaultwarden])
        XCTAssertEqual(both.hostsRefusingVPN, ["files.example.com"])
        XCTAssertEqual(relay(homeOnly: [.nextcloud], services: [.nextcloud]).hostsRefusingVPN, [])
    }

    func testTheSSHCommandCarriesTheNoVPNList() {
        XCTAssertEqual(CommandCatalog.AdminLockdown.only(hosts: ["a.example.com"]),
                       "sudo /opt/gryonixnexus-admin-lockdown.sh only a.example.com")
        XCTAssertEqual(CommandCatalog.AdminLockdown.only(hosts: ["a.example.com", "b.example.com"], denyVPN: ["b.example.com"]),
                       "sudo /opt/gryonixnexus-admin-lockdown.sh only a.example.com b.example.com --no-vpn b.example.com")
        XCTAssertTrue(CommandCatalog.AdminLockdown.only(hosts: ["a.example.com"], denyVPN: []).hasSuffix("--no-vpn"))
    }

    func testAProbeVerdictNamesOnlyTheOpenPortsAsked() {
        XCTAssertEqual(PublicPortProbe.verdict(asked: [25, 993], open: []), .closed)
        XCTAssertEqual(PublicPortProbe.verdict(asked: [25, 993], open: [993, 25, 8080]), .open([25, 993]))
    }

    func testAServiceProbesItsOwnPortsNotTheWebPorts() throws {
        let mail = try XCTUnwrap(ServiceRegistry.service(.dockerMailserver))
        let vault = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let deployment = relay(homeOnly: [.dockerMailserver], services: [.dockerMailserver, .vaultwarden])
        XCTAssertTrue(PublicPortProbe.ports(of: mail, in: deployment).contains(25))
        XCTAssertFalse(PublicPortProbe.ports(of: mail, in: deployment).contains(443))
        XCTAssertEqual(PublicPortProbe.ports(of: vault, in: deployment), [])
    }

    func testTheCertificateProfileWrapsTheDERCertificate() throws {
        let data = try XCTUnwrap(InternalCertificateProfile.mobileconfig(pem: Self.pem, serverName: "Server"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["PayloadType"] as? String, "Configuration")
        let payload = try XCTUnwrap((plist["PayloadContent"] as? [[String: Any]])?.first)
        XCTAssertEqual(payload["PayloadType"] as? String, "com.apple.security.root")
        XCTAssertEqual(payload["PayloadContent"] as? Data, InternalCertificateProfile.der(fromPEM: Self.pem))
        XCTAssertEqual((payload["PayloadUUID"] as? String)?.count, 36)
        XCTAssertNil(InternalCertificateProfile.mobileconfig(pem: "not a certificate", serverName: "Server"))
    }
}
