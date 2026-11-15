import CryptoKit
import Foundation

/// Key fingerprints and OpenSSH randomart
public enum SSHFingerprint {
    private static let width = 17
    private static let height = 9
    private static let symbols = Array(" .o+=*BOX@%&#/^SE")

    /// The decoded key blob of an authorized_keys line
    public static func blob(publicKeyLine: String) -> Data? {
        let parts = publicKeyLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return Data(base64Encoded: String(parts[1]))
    }

    public static func digest(publicKeyLine: String) -> Data? {
        blob(publicKeyLine: publicKeyLine).map { Data(SHA256.hash(data: $0)) }
    }

    /// "SHA256:" and unpadded base64, as ssh-keygen -l prints
    public static func sha256(publicKeyLine: String) -> String? {
        guard let digest = digest(publicKeyLine: publicKeyLine) else { return nil }
        let base64 = digest.base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:" + base64
    }

    public static func randomArt(publicKeyLine: String, kind: SSHKeyKind) -> String? {
        digest(publicKeyLine: publicKeyLine).map { randomArt(digest: $0, kind: kind) }
    }

    /// The drunken-bishop walk over a digest
    public static func randomArt(digest: Data, kind: SSHKeyKind) -> String {
        let field = walk(digest)
        let title = "[\(kind.artName) \(kind.bits)]"
        var lines = [border(title)]
        for y in 0..<height {
            let row = (0..<width).map { String(symbols[field[$0][y]]) }.joined()
            lines.append("|" + row + "|")
        }
        lines.append(border("[SHA256]"))
        return lines.joined(separator: "\n")
    }

    private static func walk(_ digest: Data) -> [[Int]] {
        var field = Array(repeating: Array(repeating: 0, count: height), count: width)
        var x = width / 2
        var y = height / 2
        let maxCount = symbols.count - 3
        for byte in digest {
            var input = byte
            for _ in 0..<4 {
                x = min(max(x + (input & 1 != 0 ? 1 : -1), 0), width - 1)
                y = min(max(y + (input & 2 != 0 ? 1 : -1), 0), height - 1)
                if field[x][y] < maxCount { field[x][y] += 1 }
                input >>= 2
            }
        }
        field[width / 2][height / 2] = symbols.count - 2
        field[x][y] = symbols.count - 1
        return field
    }

    private static func border(_ title: String) -> String {
        let left = (width - title.count) / 2
        let right = width - left - title.count
        return "+" + String(repeating: "-", count: left) + title
            + String(repeating: "-", count: max(right, 0)) + "+"
    }
}
