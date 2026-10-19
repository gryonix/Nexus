import Foundation

public enum ConnectEnvelope {
    public static let endOfStreamFlag: UInt8 = 0x02
    /// The largest message either side accepts
    public static let maxPayload = 16 << 20
    public static let cutOffMessage = "the connection ended before the agent finished"

    public static func encode(_ payload: Data, flags: UInt8 = 0) -> Data {
        var out = Data(capacity: 5 + payload.count)
        out.append(flags)
        let len = UInt32(payload.count)
        out.append(UInt8((len >> 24) & 0xff))
        out.append(UInt8((len >> 16) & 0xff))
        out.append(UInt8((len >> 8) & 0xff))
        out.append(UInt8(len & 0xff))
        out.append(payload)
        return out
    }

    public struct Frame: Sendable, Equatable {
        public let flags: UInt8
        public let payload: Data
        public var isEndOfStream: Bool { flags & ConnectEnvelope.endOfStreamFlag != 0 }
    }

    public struct Decoder {
        private var buffer = Data()

        public init() {}

        public mutating func append(_ data: Data) { buffer.append(data) }

        public mutating func next() throws -> Frame? {
            guard buffer.count >= 5 else { return nil }
            let start = buffer.startIndex
            let flags = buffer[start]
            let len = (UInt32(buffer[start + 1]) << 24)
                | (UInt32(buffer[start + 2]) << 16)
                | (UInt32(buffer[start + 3]) << 8)
                | UInt32(buffer[start + 4])
            guard Int(len) <= ConnectEnvelope.maxPayload else {
                throw AgentError.transport("the agent sent a message larger than \(ConnectEnvelope.maxPayload) bytes")
            }
            let total = 5 + Int(len)
            guard buffer.count >= total else { return nil }
            let payload = buffer.subdata(in: (start + 5) ..< (start + total))
            buffer.removeSubrange(start ..< (start + total))
            return Frame(flags: flags, payload: payload)
        }
    }
}
