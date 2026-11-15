import Foundation

/// Country networks cut from a downloaded geoip.dat file.

public struct AdvancedGeoIP: Codable, Equatable, Sendable {
    public static let defaultURL = "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"

    public var url: String
    /// Country code, upper case, to its CIDR networks
    public var ranges: [String: [String]]
    public var updatedAt: Date?

    public init(url: String = defaultURL, ranges: [String: [String]] = [:], updatedAt: Date? = nil) {
        self.url = url
        self.ranges = ranges
        self.updatedAt = updatedAt
    }

    /// Country codes the rules ask for
    public static func codes(in rules: [AdvancedRule]) -> Set<String> {
        Set(rules.filter { $0.kind == .geoip }.map { $0.value.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty && $0 != privateCode })
    }

    static let privateCode = "PRIVATE"

    /// Networks for one rule value, nil when unknown
    func networks(for value: String) -> [String]? {
        let code = value.trimmingCharacters(in: .whitespaces).uppercased()
        if code == Self.privateCode { return XrayConfiguration.privateRanges }
        guard let found = ranges[code], !found.isEmpty else { return nil }
        return found
    }
}

/// Reads the v2ray GeoIPList protobuf without a protobuf library.
public enum GeoIPDatParser {
    public enum Failure: Error { case malformed }

    /// Networks for the wanted codes; others are skipped unread
    public static func ranges(in data: Data, codes: Set<String>) throws -> [String: [String]] {
        var reader = ProtoReader(bytes: ArraySlice([UInt8](data)))
        var result: [String: [String]] = [:]
        while !reader.atEnd {
            let (field, wire) = try reader.key()
            guard field == 1, wire == 2 else { try reader.skip(wire); continue }
            let entry = try reader.lengthDelimited()
            if let (code, networks) = try country(entry, codes: codes) { result[code] = networks }
        }
        return result
    }

    private static func country(_ bytes: ArraySlice<UInt8>, codes: Set<String>) throws -> (String, [String])? {
        var reader = ProtoReader(bytes: bytes)
        var code = ""
        var networks: [String] = []
        while !reader.atEnd {
            let (field, wire) = try reader.key()
            switch (field, wire) {
            case (1, 2):
                code = String(decoding: try reader.lengthDelimited(), as: UTF8.self).uppercased()
                if !codes.contains(code) { return nil }
            case (2, 2):
                if let network = try cidr(try reader.lengthDelimited()) { networks.append(network) }
            default:
                try reader.skip(wire)
            }
        }
        return code.isEmpty ? nil : (code, networks)
    }

    private static func cidr(_ bytes: ArraySlice<UInt8>) throws -> String? {
        var reader = ProtoReader(bytes: bytes)
        var address: [UInt8] = []
        var prefix = 0
        while !reader.atEnd {
            let (field, wire) = try reader.key()
            switch (field, wire) {
            case (1, 2): address = Array(try reader.lengthDelimited())
            case (2, 0): prefix = Int(try reader.varint())
            default: try reader.skip(wire)
            }
        }
        if address.count == 4 { return address.map(String.init).joined(separator: ".") + "/\(prefix)" }
        guard address.count == 16 else { return nil }
        let groups = stride(from: 0, to: 16, by: 2).map { String(Int(address[$0]) << 8 | Int(address[$0 + 1]), radix: 16) }
        return groups.joined(separator: ":") + "/\(prefix)"
    }
}

struct ProtoReader {
    let bytes: ArraySlice<UInt8>
    var index: Int

    init(bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        index = bytes.startIndex
    }

    var atEnd: Bool { index >= bytes.endIndex }

    mutating func varint() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < bytes.endIndex, shift < 64 else { throw GeoIPDatParser.Failure.malformed }
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
    }

    mutating func key() throws -> (field: Int, wire: Int) {
        let raw = try varint()
        return (Int(raw >> 3), Int(raw & 7))
    }

    mutating func lengthDelimited() throws -> ArraySlice<UInt8> {
        let length = Int(try varint())
        guard length >= 0, index + length <= bytes.endIndex else { throw GeoIPDatParser.Failure.malformed }
        defer { index += length }
        return bytes[index..<index + length]
    }

    mutating func skip(_ wire: Int) throws {
        switch wire {
        case 0: _ = try varint()
        case 1: index += 8
        case 2: _ = try lengthDelimited()
        case 5: index += 4
        default: throw GeoIPDatParser.Failure.malformed
        }
        if index > bytes.endIndex { throw GeoIPDatParser.Failure.malformed }
    }
}
