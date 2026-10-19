import XCTest
@testable import gryonixNexusCore

final class DomainTests: XCTestCase {
    func testValidDomains() throws {
        XCTAssertEqual(try Domain("example.com").name, "example.com")
        XCTAssertEqual(try Domain("sub.example.co.uk").name, "sub.example.co.uk")
        XCTAssertEqual(try Domain("xn--80ak6aa92e.com").name, "xn--80ak6aa92e.com")
    }

    func testNormalization() throws {
        XCTAssertEqual(try Domain("  Example.COM \n").name, "example.com")
    }

    func testInvalidDomains() {
        for candidate in ["", "example", "exa mple.com", "-example.com", "example-.com",
                          "example.c", "example.123", ".example.com", "example..com"] {
            XCTAssertThrowsError(try Domain(candidate), "must throw for \"\(candidate)\"") { error in
                guard case ValidationError.invalidDomain = error as! ValidationError else {
                    return XCTFail("wrong error type for \"\(candidate)\": \(error)")
                }
            }
        }
    }
}

final class NetworkAddressTests: XCTestCase {
    func testValidIPv4() throws {
        XCTAssertEqual(try NetworkAddress(parsing: "203.0.113.10"), .ipv4("203.0.113.10"))
        XCTAssertEqual(try NetworkAddress(parsing: "10.8.0.1"), .ipv4("10.8.0.1"))
        XCTAssertEqual(try NetworkAddress(parsing: "0.0.0.0"), .ipv4("0.0.0.0"))
    }

    func testValidIPv6() throws {
        XCTAssertEqual(try NetworkAddress(parsing: "2001:db8::1"), .ipv6("2001:db8::1"))
        XCTAssertTrue(try NetworkAddress(parsing: "::1").value == "::1")
    }

    func testLocalOnlyAcceptsAHostname() throws {
        XCTAssertEqual(try NetworkAddress(localOnly: "orion.local"), .hostname("orion.local"))
        XCTAssertEqual(try NetworkAddress(localOnly: "  ORION.local "), .hostname("orion.local"))
        XCTAssertEqual(try NetworkAddress(localOnly: "server.lan").value, "server.lan")
        XCTAssertEqual(try NetworkAddress(localOnly: "192.168.1.50"), .ipv4("192.168.1.50"))
        XCTAssertTrue(try NetworkAddress(localOnly: "192.168.1.50").isIPv4)
        XCTAssertFalse(try NetworkAddress(localOnly: "orion.local").isIPv4)
    }

    func testStrictParserStillRejectsAHostname() {
        XCTAssertThrowsError(try NetworkAddress(parsing: "orion.local"))
    }

    func testLocalOnlyStillRejectsNonsense() {
        for candidate in ["", "orion", "not a host", "-bad.local", "256.0.0.1.2"] {
            XCTAssertThrowsError(try NetworkAddress(localOnly: candidate),
                                 "must throw for \"\(candidate)\"")
        }
    }

    func testInvalidAddresses() {
        for candidate in ["", "256.0.0.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "a.b.c.d", "10.8.0"] {
            XCTAssertThrowsError(try NetworkAddress(parsing: candidate), "must throw for \"\(candidate)\"")
        }
    }
}

final class StringTemplateRendererTests: XCTestCase {
    func testSubstitution() throws {
        let renderer = StringTemplateRenderer()
        let result = try renderer.render(
            template: "host={{host}} domain={{domain}}",
            with: ["host": "mail.example.com", "domain": "example.com"]
        )
        XCTAssertEqual(result, "host=mail.example.com domain=example.com")
    }

    func testUnresolvedPlaceholderThrows() {
        XCTAssertThrowsError(
            try StringTemplateRenderer().render(template: "host={{host}}", with: [:])
        )
    }
}

final class DefaultSecurityPolicyTests: XCTestCase {
    func testSafeDefaults() {
        let policy = DefaultSecurityPolicy()
        XCTAssertFalse(policy.allowOpenRelay, "open relay is always forbidden by default")
        XCTAssertGreaterThanOrEqual(policy.dkimKeyBits, 2048)
        XCTAssertFalse(policy.ssh.permitRootLogin)
        XCTAssertFalse(policy.ssh.passwordAuthentication)
        XCTAssertEqual(policy.minimumTLSVersion, .v1_2)
    }
}
