import Foundation

/// SSH wire-format writer for keys
public struct SSHWireWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func uint32(_ value: UInt32) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }

    public mutating func string(_ bytes: Data) {
        uint32(UInt32(bytes.count))
        data.append(bytes)
    }

    public mutating func string(_ text: String) {
        string(Data(text.utf8))
    }

    public mutating func raw(_ bytes: Data) {
        data.append(bytes)
    }

    /// Unsigned big-endian integer as an mpint
    public mutating func mpint(_ unsigned: Data) {
        let trimmed = unsigned.drop { $0 == 0 }
        var body = Data(trimmed)
        if let first = body.first, first & 0x80 != 0 { body.insert(0, at: 0) }
        string(body)
    }
}
