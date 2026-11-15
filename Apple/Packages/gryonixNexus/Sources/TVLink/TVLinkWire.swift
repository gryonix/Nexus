import Foundation

public enum TVLinkService {
    public static let type = "_gryonixnexus-tv._tcp"
    public static let protocolVersion = 1
    public static let idKey = "id"
    /// When the TV app last said it is on screen
    public static let awakeKey = "at"
    public static let awakeInterval: TimeInterval = 60
    public static let awakeFreshness: TimeInterval = 180
    public static let linkScheme = "gryonixnexus"
    public static let linkHost = "tv"
}

/// Length-prefixed frames
public enum TVFrame {
    public static let maxLength = 8 << 20

    public enum Failure: Error, Equatable {
        case tooLarge(Int)
    }

    public static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return frame
    }

    /// Pulls whole frames out of bytes arriving in arbitrary pieces
    public struct Reader: Sendable {
        private var buffer = Data()

        public init() {}

        public mutating func append(_ bytes: Data) {
            buffer.append(bytes)
        }

        /// The next complete frame, or nil until more bytes arrive
        public mutating func next() throws -> Data? {
            guard buffer.count >= 4 else { return nil }
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= TVFrame.maxLength else { throw Failure.tooLarge(length) }
            guard buffer.count >= 4 + length else { return nil }
            let payload = Data(buffer[start + 4..<start + 4 + length])
            buffer = Data(buffer[(start + 4 + length)...])
            return payload
        }
    }
}

/// The JSON both platforms write, byte for byte
public enum TVJSON {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }
}

/// A plaintext message of the handshake, before any key exists
public struct TVHandshakeMessage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello, commit, reveal, error
    }

    public enum Mode: String, Codable, Sendable {
        /// First contact: the code on the TV decides
        case pair
        /// A phone the TV already knows
        case session
    }

    public enum Refusal: String, Codable, Sendable, Error {
        case wrongCode = "wrong-code"
        /// Another phone is pairing right now
        case busy
        case unknownPhone = "unknown-phone"
        /// The peer speaks a newer protocol
        case version
        /// Anything the peer sent out of order
        case protocolError = "protocol"
    }

    public var code: Refusal?
    public var id: String?
    public var key: Data?
    public var mode: Mode?
    public var name: String?
    public var nonce: Data?
    public var round: Int?
    public var t: Kind
    public var v: Int?
    public var value: Data?

    public init(t: Kind, v: Int? = nil, mode: Mode? = nil, id: String? = nil, name: String? = nil,
                key: Data? = nil, nonce: Data? = nil, round: Int? = nil, value: Data? = nil,
                code: Refusal? = nil) {
        self.t = t
        self.v = v
        self.mode = mode
        self.id = id
        self.name = name
        self.key = key
        self.nonce = nonce
        self.round = round
        self.value = value
        self.code = code
    }

    public static func refusal(_ code: Refusal) -> TVHandshakeMessage {
        TVHandshakeMessage(t: .error, code: code)
    }
}

public struct TVSentServer: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var transfer: Data?

    public init(id: String, name: String, transfer: Data?) {
        self.id = id
        self.name = name
        self.transfer = transfer
    }

    public var withoutTransfer: TVSentServer {
        TVSentServer(id: id, name: name, transfer: nil)
    }
}

public struct TVLicenceVouch: Codable, Equatable, Sendable {
    public var active: Bool
    /// The phone's installation id the signed token is bound to
    public var device: String?
    /// Seconds since 1970; nil for a lifetime license
    public var expires: Int?
    public var plan: String?
    public var token: String?

    public init(active: Bool, plan: String? = nil, expires: Int? = nil, token: String? = nil,
                device: String? = nil) {
        self.active = active
        self.plan = plan
        self.expires = expires
        self.token = token
        self.device = device
    }
}

/// An encrypted request or answer, once the handshake is done
public struct TVMessage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Phone: what did I send you? TV: `servers`
        case list
        /// Phone: keep these servers. TV: `servers`
        case put
        /// Phone: here is my license, nothing else. TV: `ok`
        case licence
        /// Phone: forget me. TV: `ok`
        case unpair
        case paired
        case servers
        case ok
        case error
    }

    public var code: String?
    public var items: [TVSentServer]?
    public var licence: TVLicenceVouch?
    public var t: Kind

    public init(t: Kind, items: [TVSentServer]? = nil, licence: TVLicenceVouch? = nil, code: String? = nil) {
        self.t = t
        self.items = items
        self.licence = licence
        self.code = code
    }
}
