import Foundation

public struct DNSRecord: Sendable, Hashable {
    public enum RecordType: String, Sendable, Hashable {
        case a = "A"
        case aaaa = "AAAA"
        case mx = "MX"
        case txt = "TXT"
        case srv = "SRV"
    }

    /// The four fields an SRV record actually carries
    public struct SRVData: Sendable, Hashable {
        public let priority: Int
        public let weight: Int
        public let port: Int
        public let target: String

        public init(priority: Int, weight: Int, port: Int, target: String) {
            self.priority = priority
            self.weight = weight
            self.port = port
            self.target = target
        }

        /// Zone-file rdata: `<priority> <weight> <port> <target>.`
        public var zoneRData: String { "\(priority) \(weight) \(port) \(target)." }
    }

    public let name: String
    public let type: RecordType
    public let value: String
    /// MX preference; nil for other types
    public let priority: Int?
    /// The SRV parts, and only for `.srv`
    public let srv: SRVData?
    /// Human-readable purpose, rendered as a comment in manual exports
    public let comment: String?

    public init(name: String, type: RecordType, value: String,
                priority: Int? = nil, srv: SRVData? = nil, comment: String? = nil) {
        self.name = name
        self.type = type
        self.value = value
        self.priority = priority
        self.srv = srv
        self.comment = comment
    }

    public static func service(name: String, srv: SRVData, comment: String? = nil) -> DNSRecord {
        DNSRecord(name: name, type: .srv,
                  value: "\(srv.priority) \(srv.weight) \(srv.port) \(srv.target)",
                  priority: srv.priority, srv: srv, comment: comment)
    }
}

public func bindTXTRData(_ value: String, chunkSize: Int = 255) -> String {
    func quoted(_ part: some StringProtocol) -> String {
        // Backslash first: escaping the quotes would otherwise be re-escaped.
        let escaped = part
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    let bytes = Array(value.utf8)
    guard bytes.count > chunkSize else { return quoted(value) }
    return stride(from: 0, to: bytes.count, by: chunkSize)
        .map { start -> String in
            let end = min(start + chunkSize, bytes.count)
            return quoted(String(decoding: bytes[start..<end], as: UTF8.self))
        }
        .joined(separator: " ")
}

extension DNSRecord {
    /// Whether this record may overwrite that existing value
    public func replaces(existingValue: String) -> Bool {
        guard type == .txt else { return true }
        return Self.txtKind(existingValue) == Self.txtKind(value)
    }

    /// The SPF, DMARC or DKIM tag; other TXT are unique
    static func txtKind(_ raw: String) -> String {
        let value = raw.filter { $0 != "\"" }.trimmingCharacters(in: .whitespaces)
        let tag = value.prefix { $0 != " " && $0 != ";" }.lowercased()
        return tag.hasPrefix("v=") ? tag : "other:\(value)"
    }
}

extension DNSRecord {
    public static func merging(_ records: [DNSRecord],
                               existing: (DNSRecord) -> String?) -> [DNSRecord] {
        records.map { record in existing(record).map(record.merged(withExisting:)) ?? record }
    }

    public func merged(withExisting existingValue: String) -> DNSRecord {
        guard type == .txt, Self.txtKind(value) == "v=spf1",
              Self.txtKind(existingValue) == "v=spf1" else { return self }
        return DNSRecord(name: name, type: type, value: Self.mergedSPF(existing: existingValue, ours: value),
                         priority: priority, srv: srv, comment: comment)
    }

    static func mergedSPF(existing: String, ours: String) -> String {
        func mechanisms(_ raw: String) -> [String] {
            raw.filter { $0 != "\"" }.split(separator: " ").map(String.init)
                .filter { $0.lowercased() != "v=spf1" }
        }
        func isAll(_ token: String) -> Bool {
            let bare = token.lowercased().drop { "+-~?".contains($0) }
            return bare == "all"
        }
        let owners = mechanisms(existing), mine = mechanisms(ours)
        var kept = owners.filter { !isAll($0) }
        for token in mine where !isAll(token) && !kept.contains(where: { $0.lowercased() == token.lowercased() }) {
            kept.append(token)
        }
        let closing = owners.first(where: isAll) ?? mine.first(where: isAll)
        return (["v=spf1"] + kept + (closing.map { [$0] } ?? [])).joined(separator: " ")
    }
}

extension DNSRecord {
    public func updatedSet(existing: [String], target: (DNSRecord) -> String) -> [String]? {
        let wanted = target(self)
        guard type == .txt else {
            let present = existing.contains {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == wanted.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            return present ? nil : existing + [wanted]
        }
        func plain(_ value: String) -> String { value.filter { $0 != "\"" } }
        let kind = Self.txtKind(value)
        let sameKind = existing.filter { Self.txtKind(plain($0)) == kind }
        let others = existing.filter { Self.txtKind(plain($0)) != kind }
        var final = self
        if kind == "v=dmarc1", !sameKind.isEmpty { return nil }
        if kind == "v=spf1", let owners = sameKind.first { final = merged(withExisting: plain(owners)) }
        let result = others + [target(final)]
        return Set(result) == Set(existing) && result.count == existing.count ? nil : result
    }
}
