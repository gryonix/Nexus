import CryptoKit
import XCTest
import gryonixNexusCore

@testable import gryonixNexus

/// Which of demo, active and expired a copy is in.
@MainActor
final class LicenseStatusTests: XCTestCase {
    private let signer = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 7, count: 32))
    private let device = "5A1F3C2E-0000-4000-8000-000000000001"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func signed(plan: String, expires: Int?) -> String {
        var fields = ["\"dev\":\"\(device)\"", "\"iat\":1800000000", "\"lic\":\"0123456789abcdef\"",
                      "\"plan\":\"\(plan)\"", "\"prod\":\"nexus\"", "\"v\":1"]
        if let expires { fields.append("\"exp\":\(expires)") }
        let data = Data("{\(fields.sorted().joined(separator: ","))}".utf8)
        let signature = try! signer.signature(for: data)
        return "\(base64URL(data)).\(base64URL(signature))"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private var subscription: String { signed(plan: "monthly", expires: 1_802_851_200) }
    private var lifetime: String { signed(plan: "lifetime", expires: nil) }

    private func token(_ text: String) throws -> LicenseToken {
        try LicenseToken.verify(text, device: device, now: now,
                                publicKey: signer.publicKey.rawRepresentation.base64EncodedString())
    }

    func testACopyWithNothingIsInDemo() {
        XCTAssertEqual(LicenseStore.derive(token: nil, appStore: nil, everActive: false), .demo)
    }

    func testACopyThatWasLicensedBeforeIsExpired() {
        XCTAssertEqual(LicenseStore.derive(token: nil, appStore: nil, everActive: true), .expired)
    }

    func testASignedTokenUnlocksWithItsPlanAndEnd() throws {
        let signed = try token(subscription)
        let status = LicenseStore.derive(token: signed, appStore: nil, everActive: false)
        XCTAssertEqual(status, .active(plan: .monthly, expires: signed.expires, viaAppStore: false))
        XCTAssertTrue(status.isActive)
    }

    func testAnAppStoreSubscriptionUnlocksWithoutACode() {
        let end = now.addingTimeInterval(86_400)
        let status = LicenseStore.derive(token: nil, appStore: (.yearly, end), everActive: false)
        XCTAssertEqual(status, .active(plan: .yearly, expires: end, viaAppStore: true))
    }

    func testAnAppStoreLifetimeBeatsACode() throws {
        let status = LicenseStore.derive(token: try token(subscription), appStore: (.lifetime, nil),
                                         everActive: false)
        XCTAssertEqual(status, .active(plan: .lifetime, expires: nil, viaAppStore: true))
    }

    func testACodeBeatsAnAppStoreSubscription() throws {
        let signed = try token(lifetime)
        let status = LicenseStore.derive(token: signed, appStore: (.monthly, now), everActive: false)
        XCTAssertEqual(status, .active(plan: .lifetime, expires: nil, viaAppStore: false))
    }

    func testOnlyAnActiveStatusUnlocks() {
        XCTAssertFalse(LicenseStore.Status.demo.isActive)
        XCTAssertFalse(LicenseStore.Status.expired.isActive)
    }
}
