import Compression
import Foundation

/// An Amnezia `vpn://` key holding a WireGuard or AmneziaWG tunnel
enum AmneziaKey {
    struct Decoded: Equatable {
        let config: String
        let name: String?
    }

    static let scheme = "vpn://"

    /// The key inside the text, if any
    static func link(in text: String) -> String? {
        guard let start = text.range(of: scheme) else { return nil }
        let rest = text[start.upperBound...]
        let body = rest.prefix { !$0.isWhitespace }
        return body.isEmpty ? nil : String(body)
    }

    static func decode(_ body: String) throws -> Decoded {
        guard let data = base64URL(body) else { throw ForeignTunnelConfig.Failure.unreadable }
        let json = inflated(data) ?? data
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let config = tunnelConfig(in: root) else { throw ForeignTunnelConfig.Failure.unreadable }
        return Decoded(config: filled(config, from: root), name: root["description"] as? String)
    }

    private static func base64URL(_ body: String) -> Data? {
        var text = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        return Data(base64Encoded: text)
    }

    /// Undoes Qt's qCompress: a length, then a zlib stream
    static func inflated(_ data: Data) -> Data? {
        guard data.count > 6, data[data.startIndex + 4] == 0x78 else { return nil }
        let size = data.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        guard size > 0, size < 4_000_000 else { return nil }
        let deflate = data.dropFirst(6)
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            deflate.withUnsafeBytes { input in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress!, deflate.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? output : nil
    }

    /// The `wg-quick` text of the first WireGuard-like container
    private static func tunnelConfig(in root: [String: Any]) -> String? {
        let containers = root["containers"] as? [[String: Any]] ?? []
        for container in containers {
            for key in ["awg", "wireguard"] {
                guard let part = container[key] as? [String: Any],
                      let last = part["last_config"] as? String,
                      let data = last.data(using: .utf8),
                      let inner = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let config = inner["config"] as? String else { continue }
                return config
            }
        }
        return nil
    }

    /// Fills the DNS placeholders Amnezia leaves in the text
    private static func filled(_ config: String, from root: [String: Any]) -> String {
        let primary = root["dns1"] as? String ?? "1.1.1.1"
        let secondary = root["dns2"] as? String ?? "1.0.0.1"
        return config
            .replacingOccurrences(of: "$PRIMARY_DNS", with: primary)
            .replacingOccurrences(of: "$SECONDARY_DNS", with: secondary)
    }
}
