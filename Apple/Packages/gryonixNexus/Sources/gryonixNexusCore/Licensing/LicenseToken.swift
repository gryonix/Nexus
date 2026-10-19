import CryptoKit
import Foundation

/// A signed permission for one device, checked offline.
public struct LicenseToken: Equatable, Sendable {
    public enum Plan: String, Codable, Sendable {
        case monthly, yearly, lifetime
    }

    public enum Product: String, Codable, Sendable {
        case nexus, vpn, bundle

        public func covers(_ app: Product) -> Bool {
            self == .bundle || self == app
        }
    }

    public enum VerificationError: Error, Equatable, Sendable {
        case malformed
        case badSignature
        case otherDevice
        case otherProduct
        case expired(on: Date)
    }

    public let device: String
    public let license: String
    public let plan: Plan
    public let product: Product
    public let issued: Date
    /// Nil for a lifetime license.
    public let expires: Date?

    /// The public half of the key gryonix.com signs with.
    public static let productionKey = "Z+t5tcFWudIouFWnpjgf82+2KGtpQD7lodD0f7smoDc="

    private struct Payload: Decodable {
        let dev: String
        let exp: Int?
        let iat: Int
        let lic: String
        let plan: Plan
        let prod: Product
        let v: Int
    }

    public static func verify(_ text: String, device: String, app: Product = .nexus, now: Date = Date(),
                              publicKey base64: String = productionKey) throws -> LicenseToken {
        guard let keyData = Data(base64Encoded: base64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw VerificationError.malformed
        }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 2,
              let data = Data(licenseBase64URL: String(parts[0])),
              let signature = Data(licenseBase64URL: String(parts[1])) else {
            throw VerificationError.malformed
        }
        guard key.isValidSignature(signature, for: data) else { throw VerificationError.badSignature }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.v == 1 else {
            throw VerificationError.malformed
        }
        return try token(from: payload, device: device, app: app, now: now)
    }

    private static func token(from payload: Payload, device: String, app: Product,
                              now: Date) throws -> LicenseToken {
        guard payload.dev == device else { throw VerificationError.otherDevice }
        guard payload.prod.covers(app) else { throw VerificationError.otherProduct }
        let expires = payload.exp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        if let expires, expires < now { throw VerificationError.expired(on: expires) }
        return LicenseToken(device: payload.dev, license: payload.lic, plan: payload.plan,
                            product: payload.prod,
                            issued: Date(timeIntervalSince1970: TimeInterval(payload.iat)),
                            expires: expires)
    }
}

/// Activation codes as people type them.
public enum ActivationCode {
    private static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Canonical "XXXXX-XXXXX-XXXXX-XXXXX", or nil.
    public static func normalize(_ input: String) -> String? {
        let cleaned = input.uppercased()
            .filter { $0.isLetter || $0.isNumber }
            .map { $0 == "O" ? "0" : ($0 == "I" || $0 == "L") ? "1" : $0 }
        guard cleaned.count == 20, cleaned.allSatisfy(alphabet.contains) else { return nil }
        let text = String(cleaned)
        return stride(from: 0, to: 20, by: 5).map { start -> String in
            let from = text.index(text.startIndex, offsetBy: start)
            return String(text[from..<text.index(from, offsetBy: 5)])
        }.joined(separator: "-")
    }
}

extension Data {
    init?(licenseBase64URL text: String) {
        var padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        if padded.count % 4 != 0 { padded += String(repeating: "=", count: 4 - padded.count % 4) }
        self.init(base64Encoded: padded)
    }
}
