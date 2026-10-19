import CryptoKit
import Foundation

enum DevicePushProof {
    private static let account = "push.device-secret"

    static var secret: String {
        let store = KeychainStore()
        if let data = try? store.data(for: account), let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        let fresh = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        try? store.set(Data(fresh.utf8), for: account)
        return fresh
    }

    static var proof: String { hash(of: secret) }

    static func hash(of secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum PushRelays {
    private static let key = "push.relays"

    static var known: [String] {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Array(Set([NotifyDraft.defaultRelayURL] + saved)).sorted()
    }

    static func remember(_ url: String) {
        guard url.hasPrefix("https://") else { return }
        var saved = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        saved.insert(url)
        UserDefaults.standard.set(Array(saved), forKey: key)
    }

    static func serversHolding(token: String) async -> Int {
        await total(token: token, method: "GET", field: "servers")
    }

    static func stopAll(token: String) async -> Int {
        await total(token: token, method: "DELETE", field: "removed")
    }

    private static func total(token: String, method: String, field: String) async -> Int {
        var sum = 0
        for relay in known {
            guard let url = URL(string: "\(relay)/v1/devices/\(token)") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = method
            request.setValue(DevicePushProof.secret, forHTTPHeaderField: "x-gryonix-device-secret")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let count = json[field] as? Int else { continue }
            sum += count
        }
        return sum
    }
}
