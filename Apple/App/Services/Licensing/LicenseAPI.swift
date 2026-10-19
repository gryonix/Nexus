import Foundation

/// Calls to the license server on gryonix.com.
enum LicenseAPI {
    static let base = URL(string: "https://gryonix.com/api/")!
    /// The app named in requests.
    static let app = "nexus"

    struct Grant: Decodable {
        let token: String?
        let code: String?
        let plan: String?
        let expires: Int?
    }

    struct Device: Decodable, Identifiable {
        let device: String
        let name: String?
        let platform: String?
        var id: String { device }
    }

    struct DeviceList: Decodable {
        let limit: Int
        let devices: [Device]
    }

    enum Failure: LocalizedError, Equatable {
        case unknownCode, expired, revoked, deviceLimit, wrongProduct, pending, offline, rejected

        var errorDescription: String? {
            switch self {
            case .unknownCode: return UIL10n.string("This activation code does not exist. Check it and try again.")
            case .expired: return UIL10n.string("The subscription for this code has ended.")
            case .revoked: return UIL10n.string("This purchase was refunded, so the code no longer works.")
            case .deviceLimit: return UIL10n.string("This code is already used on five devices. Remove one of them first.")
            case .wrongProduct: return UIL10n.string("This code unlocks gryonixVPN only. gryonixNexus needs its own code, or the code of the bundle.")
            case .pending: return UIL10n.string("Waiting for the other device.")
            case .offline: return UIL10n.string("The license server could not be reached. Check the connection and try again.")
            case .rejected: return UIL10n.string("The license server did not accept this request.")
            }
        }
    }

    static func activate(code: String) async throws -> Grant {
        try await post("activate", ["code": code, "device": DeviceIdentity.uid, "app": app,
                                    "name": deviceName, "platform": platform])
    }

    static func deactivate(code: String, device: String) async throws {
        let _: Grant = try await post("deactivate", ["code": code, "device": device])
    }

    /// Marks the license as used.
    static func markUsed(code: String, device: String) async throws {
        let _: UsedAnswer = try await post("used", ["code": code, "device": device])
    }

    private struct UsedAnswer: Decodable { let ok: Bool? }

    static func devices(code: String) async throws -> DeviceList {
        try await post("devices", ["code": code])
    }

    static func claimApple(jws: String) async throws -> Grant {
        try await post("apple/claim", ["jws": jws])
    }

    static func startPairing() async throws -> String {
        struct Started: Decodable { let nonce: String }
        let started: Started = try await post("pair/start", ["device": DeviceIdentity.uid])
        return started.nonce
    }

    static func approvePairing(nonce: String, code: String) async throws {
        let _: Grant = try await post("pair/approve", ["nonce": nonce, "code": code, "app": app, "name": "Mac"])
    }

    static func pollPairing(nonce: String) async throws -> Grant {
        try await post("pair/poll", ["nonce": nonce, "device": DeviceIdentity.uid])
    }

    private static func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw failure(status: status, data: data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func failure(status: Int, data: Data) -> Failure {
        struct Answer: Decodable { let error: String? }
        switch (try? JSONDecoder().decode(Answer.self, from: data))?.error {
        case "unknown_code": return .unknownCode
        case "expired": return .expired
        case "revoked": return .revoked
        case "device_limit": return .deviceLimit
        case "wrong_product": return .wrongProduct
        default: return status == 202 ? .pending : .rejected
        }
    }

    private static var platform: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }

    private static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "iPhone"
        #endif
    }
}
