import Foundation

public protocol TVSecretStoring: Sendable {
    func store(_ secret: String, for account: String) throws
    func secret(for account: String) -> String?
    func delete(_ account: String)
}

public enum TVLinkStoreError: Error, Equatable {
    /// A server the TV could not read
    case unusable(String)
    case cannotWrite
}

/// A phone this TV paired with
public struct TVPairedPhone: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var pairedAt: Date
    public var lastSeen: Date
    /// What the phone last said about its license, and when
    public var licence: TVLicenceVouch?
    public var licenceAt: Date?
    /// Servers this phone sent, without their bundles
    public var received: [TVSentServer]

    public init(id: String, name: String, pairedAt: Date, lastSeen: Date,
                licence: TVLicenceVouch? = nil, licenceAt: Date? = nil, received: [TVSentServer] = []) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.licence = licence
        self.licenceAt = licenceAt
        self.received = received
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        pairedAt = try container.decode(Date.self, forKey: .pairedAt)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        licence = try container.decodeIfPresent(TVLicenceVouch.self, forKey: .licence)
        licenceAt = try container.decodeIfPresent(Date.self, forKey: .licenceAt)
        received = try container.decodeIfPresent([TVSentServer].self, forKey: .received) ?? []
    }
}

/// A TV this phone paired with
public struct TVPairedTV: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var address: TVAddress?
    public var pairedAt: Date
    /// When the TV last heard this phone's license
    public var vouchedAt: Date?
    public var sent: [TVSentServer]

    public init(id: String, name: String, address: TVAddress?, pairedAt: Date,
                vouchedAt: Date? = nil, sent: [TVSentServer] = []) {
        self.id = id
        self.name = name
        self.address = address
        self.pairedAt = pairedAt
        self.vouchedAt = vouchedAt
        self.sent = sent
    }
}

public struct TVPeerStore<Record: Codable & Identifiable & Sendable>: @unchecked Sendable where Record.ID == String {
    private let file: TVJSONFile<[Record]>
    private let secrets: TVSecretStoring
    private let keyPrefix: String
    private let lock = NSLock()

    public init(fileURL: URL, secrets: TVSecretStoring, keyPrefix: String) {
        self.file = TVJSONFile(url: fileURL)
        self.secrets = secrets
        self.keyPrefix = keyPrefix
    }

    public func all() -> [Record] {
        lock.withLock { file.read() ?? [] }
    }

    public func record(_ id: String) -> Record? {
        all().first { $0.id == id }
    }

    public func save(_ record: Record, pairingKey: Data? = nil) throws {
        try lock.withLock {
            if let pairingKey {
                try secrets.store(pairingKey.base64EncodedString(), for: account(record.id))
            }
            var records = file.read() ?? []
            records.removeAll { $0.id == record.id }
            records.append(record)
            guard file.write(records) else { throw TVLinkStoreError.cannotWrite }
        }
    }

    public func pairingKey(_ id: String) -> Data? {
        secrets.secret(for: account(id)).flatMap { Data(base64Encoded: $0) }
    }

    public func remove(_ id: String) {
        lock.withLock {
            secrets.delete(account(id))
            var records = file.read() ?? []
            records.removeAll { $0.id == id }
            file.write(records)
        }
    }

    private func account(_ id: String) -> String { "\(keyPrefix).\(id)" }
}

public typealias TVPhoneStore = TVPeerStore<TVPairedPhone>
public typealias TVPairedTVStore = TVPeerStore<TVPairedTV>

extension TVPeerStore where Record == TVPairedPhone {
    public init(fileURL: URL, secrets: TVSecretStoring) {
        self.init(fileURL: fileURL, secrets: secrets, keyPrefix: "tvlink.phone")
    }
}

extension TVPeerStore where Record == TVPairedTV {
    public init(fileURL: URL, secrets: TVSecretStoring) {
        self.init(fileURL: fileURL, secrets: secrets, keyPrefix: "tvlink.tv")
    }
}

/// A JSON file written whole and atomically
struct TVJSONFile<Value: Codable>: Sendable {
    let url: URL

    func read() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    @discardableResult
    func write(_ value: Value) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Secrets kept in memory, for tests and previews
public final class TVMemorySecrets: TVSecretStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func store(_ secret: String, for account: String) throws {
        lock.withLock { values[account] = secret }
    }

    public func secret(for account: String) -> String? {
        lock.withLock { values[account] }
    }

    public func delete(_ account: String) {
        lock.withLock { values[account] = nil }
    }
}
