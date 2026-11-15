import Foundation

/// What the transfer QR code carries: session, key, addresses
public struct QuickTransferTicket: Equatable, Sendable {
    public static let prefix = "GXT1"
    public static let sessionLength = 16
    public static let keyLength = 32

    public var session: Data
    public var key: Data
    public var port: UInt16
    public var addresses: [String]

    public init(session: Data, key: Data, port: UInt16, addresses: [String]) {
        self.session = session
        self.key = key
        self.port = port
        self.addresses = addresses
    }

    /// A new ticket with random session and key
    public static func fresh(port: UInt16, addresses: [String]) -> QuickTransferTicket {
        QuickTransferTicket(session: TransferSeal.randomBytes(sessionLength),
                            key: TransferSeal.randomBytes(keyLength),
                            port: port, addresses: addresses)
    }

    /// The text put into the QR code
    public var text: String {
        [Self.prefix, Base64URL.encode(session), Base64URL.encode(key), String(port),
         addresses.joined(separator: ",")].joined(separator: ";")
    }

    public init?(text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, parts[0] == Self.prefix,
              let session = Base64URL.decode(parts[1]), session.count == Self.sessionLength,
              let key = Base64URL.decode(parts[2]), key.count == Self.keyLength,
              let port = UInt16(parts[3]) else { return nil }
        let addresses = parts[4].split(separator: ",").map(String.init).filter(Self.isAddress)
        self.init(session: session, key: key, port: port, addresses: addresses)
    }

    /// Bluetooth service the sender advertises for this session
    public var bluetoothService: UUID {
        let b = [UInt8](session)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    static func isAddress(_ text: String) -> Bool {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { UInt8($0) != nil }
    }
}

/// Base64 without padding, URL-safe alphabet
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        return Data(base64Encoded: standard)
    }
}
