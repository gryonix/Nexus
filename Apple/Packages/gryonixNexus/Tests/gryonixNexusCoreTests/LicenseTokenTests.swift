import CryptoKit
import Foundation
import XCTest
@testable import gryonixNexusCore

/// Tokens signed with a throwaway key.
final class LicenseTokenTests: XCTestCase {
    static let signer = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 7, count: 32))
    static let key = signer.publicKey.rawRepresentation.base64EncodedString()
    static let device = "5A1F3C2E-0000-4000-8000-000000000001"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let monthEnd = 1_802_851_200

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func token(product: String? = "nexus", plan: String = "monthly", expires: Int? = monthEnd,
                      device: String = device) -> String {
        var fields = ["\"dev\":\"\(device)\"", "\"iat\":1800000000", "\"lic\":\"0123456789abcdef\"",
                      "\"plan\":\"\(plan)\"", "\"v\":1"]
        if let expires { fields.append("\"exp\":\(expires)") }
        if let product { fields.append("\"prod\":\"\(product)\"") }
        let data = Data("{\(fields.sorted().joined(separator: ","))}".utf8)
        let signature = try! signer.signature(for: data)
        return "\(base64URL(data)).\(base64URL(signature))"
    }

    private func verify(_ token: String, device: String = device,
                        at now: Date = now) throws -> LicenseToken {
        try LicenseToken.verify(token, device: device, now: now, publicKey: Self.key)
    }

    func testSubscriptionCarriesPlanProductAndEnd() throws {
        let token = try verify(Self.token())
        XCTAssertEqual(token.plan, .monthly)
        XCTAssertEqual(token.product, .nexus)
        XCTAssertEqual(token.expires, Date(timeIntervalSince1970: TimeInterval(Self.monthEnd)))
        XCTAssertEqual(token.license, "0123456789abcdef")
    }

    func testLifetimeNeverExpires() throws {
        let farFuture = Date(timeIntervalSince1970: 4_000_000_000)
        let token = try verify(Self.token(plan: "lifetime", expires: nil), at: farFuture)
        XCTAssertEqual(token.plan, .lifetime)
        XCTAssertNil(token.expires)
    }

    func testSubscriptionEndsAfterItsDate() {
        let after = Date(timeIntervalSince1970: TimeInterval(Self.monthEnd + 1))
        let end = Date(timeIntervalSince1970: TimeInterval(Self.monthEnd))
        XCTAssertThrowsError(try verify(Self.token(), at: after)) { error in
            XCTAssertEqual(error as? LicenseToken.VerificationError, .expired(on: end))
        }
    }

    func testTokenBelongsToOneDevice() {
        XCTAssertThrowsError(try verify(Self.token(), device: "5A1F3C2E-0000-4000-8000-000000000002")) { error in
            XCTAssertEqual(error as? LicenseToken.VerificationError, .otherDevice)
        }
    }

    func testBundleOpensThisApp() throws {
        XCTAssertEqual(try verify(Self.token(product: "bundle")).product, .bundle)
    }

    func testVPNLicenseDoesNotOpenThisApp() {
        XCTAssertThrowsError(try verify(Self.token(product: "vpn"))) { error in
            XCTAssertEqual(error as? LicenseToken.VerificationError, .otherProduct)
        }
    }

    func testTokenWithoutProductIsMalformed() {
        XCTAssertThrowsError(try verify(Self.token(product: nil))) { error in
            XCTAssertEqual(error as? LicenseToken.VerificationError, .malformed)
        }
    }

    func testChangedPayloadFailsSignature() {
        let signature = Self.token().split(separator: ".")[1]
        let forged = Self.base64URL(Data(#"{"dev":"\#(Self.device)","iat":1,"lic":"x","plan":"lifetime","prod":"nexus","v":1}"#.utf8))
        XCTAssertThrowsError(try verify("\(forged).\(signature)")) { error in
            XCTAssertEqual(error as? LicenseToken.VerificationError, .badSignature)
        }
    }

    func testProductionKeyRejectsTestTokens() {
        XCTAssertThrowsError(try LicenseToken.verify(Self.token(), device: Self.device, now: Self.now)) { error in
            XCTAssertEqual(error as? LicenseToken.VerificationError, .badSignature)
        }
    }

    func testCodesAreNormalised() {
        XCTAssertEqual(ActivationCode.normalize("abcde fghjk mnpqr stvwx"), "ABCDE-FGHJK-MNPQR-STVWX")
        XCTAssertEqual(ActivationCode.normalize("OOOOO-IIIII-LLLLL-00000"), "00000-11111-11111-00000")
        XCTAssertNil(ActivationCode.normalize("UUUUU-UUUUU-UUUUU-UUUUU"))
        XCTAssertNil(ActivationCode.normalize("ABCDE"))
    }
}
