import CryptoKit
import Foundation

/// Moves the session card from the tunnel through the relay
public final class TunnelActivityRelay: @unchecked Sendable {
    struct Identity: Codable {
        var id: String
        var key: String
        var registeredAt: String?
    }

    private let identityURL: URL?
    private let session: URLSession

    public init(groupIdentifier: String = AppGroup.identifier, session: URLSession = .shared) {
        identityURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("tunnel-relay-identity")
        self.session = session
    }

    /// Sends one card update; false when the relay refused it
    @discardableResult
    public func send(_ body: [String: Any], ticket: TunnelActivityTicket) async -> Bool {
        guard var identity = loadIdentity(), let relay = URL(string: ticket.relayURL) else { return false }
        if identity.registeredAt != ticket.relayURL {
            guard await register(identity, relay: relay) else { return false }
            identity.registeredAt = ticket.relayURL
            save(identity)
        }
        var payload = body
        payload["token"] = ticket.token
        let status = await post(payload, identity: identity, relay: relay)
        guard status == 404 else { return status == 204 }
        identity.registeredAt = nil
        save(identity)
        return false
    }

    private func register(_ identity: Identity, relay: URL) async -> Bool {
        guard let key = signingKey(identity) else { return false }
        let body = ["public_key": key.publicKey.rawRepresentation.base64EncodedString()]
        let status = await call("PUT", "/v1/servers/\(identity.id)", body: body, key: key, relay: relay)
        return status == 204
    }

    private func post(_ body: [String: Any], identity: Identity, relay: URL) async -> Int {
        guard let key = signingKey(identity) else { return 0 }
        return await call("POST", "/v1/servers/\(identity.id)/live", body: body, key: key, relay: relay)
    }

    private func call(_ method: String, _ path: String, body: [String: Any],
                      key: Curve25519.Signing.PrivateKey, relay: URL) async -> Int {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return 0 }
        var request = URLRequest(url: relay.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.httpBody = data
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (name, value) in Self.signature(method: method, path: path, body: data, key: key) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let response = try? await session.data(for: request)
        return (response?.1 as? HTTPURLResponse)?.statusCode ?? 0
    }

    /// The relay's request signature headers
    static func signature(method: String, path: String, body: Data, key: Curve25519.Signing.PrivateKey,
                          now: Date = Date()) -> [String: String] {
        let stamp = String(Int(now.timeIntervalSince1970))
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let message = Data("\(method)\n\(path)\n\(stamp)\n\(digest)".utf8)
        let signed = (try? key.signature(for: message))?.base64EncodedString() ?? ""
        return ["x-gryonix-timestamp": stamp, "x-gryonix-signature": signed]
    }

    private func signingKey(_ identity: Identity) -> Curve25519.Signing.PrivateKey? {
        Data(base64Encoded: identity.key).flatMap { try? Curve25519.Signing.PrivateKey(rawRepresentation: $0) }
    }

    private func loadIdentity() -> Identity? {
        if let url = identityURL, let data = try? Data(contentsOf: url),
           let kept = try? JSONDecoder().decode(Identity.self, from: data) {
            return kept
        }
        let random = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let made = Identity(id: "tunnel-\(random)",
                            key: Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString())
        save(made)
        return identityURL == nil ? nil : made
    }

    private func save(_ identity: Identity) {
        guard let url = identityURL, let data = try? JSONEncoder().encode(identity) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
