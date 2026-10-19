/// Whether a server can carry the chosen services
public struct HardwareVerdict: Sendable, Hashable {
    public enum Level: Int, Sendable, Comparable {
        case fits, tight, doesNotFit

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Resource: String, Sendable { case memory, disk }

    public struct Finding: Sendable, Hashable {
        public let resource: Resource
        public let level: Level
        public let haveBytes: Int64
        public let needBytes: Int64
        /// Swap counted toward memory, zero otherwise
        public var swapBytes: Int64 = 0
    }

    public let findings: [Finding]

    public var level: Level { findings.map(\.level).max() ?? .fits }

    /// Headroom below which a fit reads as tight
    static let comfort = 1.25

    public static func judge(_ hardware: ServerHardware,
                             against requirements: ServerRequirements) -> HardwareVerdict {
        let mebibyte: Int64 = 1_048_576
        let gibibyte: Int64 = 1_073_741_824
        return HardwareVerdict(findings: [
            memory(hardware, need: Int64(requirements.memoryMB) * mebibyte),
            finding(.disk, have: hardware.rootFreeBytes,
                    need: Int64(requirements.diskGB) * gibibyte),
        ])
    }

    /// Too little memory is only tight when swap covers it
    private static func memory(_ hardware: ServerHardware, need: Int64) -> Finding {
        var found = finding(.memory, have: hardware.memoryBytes, need: need)
        guard found.level == .doesNotFit, hardware.swapBytes > 0 else { return found }
        found.swapBytes = hardware.swapBytes
        if hardware.memoryBytes + hardware.swapBytes >= need {
            found = Finding(resource: .memory, level: .tight, haveBytes: hardware.memoryBytes,
                            needBytes: need, swapBytes: hardware.swapBytes)
        }
        return found
    }

    private static func finding(_ resource: Resource, have: Int64, need: Int64) -> Finding {
        let level: Level
        if have < need {
            level = .doesNotFit
        } else if Double(have) < Double(need) * comfort {
            level = .tight
        } else {
            level = .fits
        }
        return Finding(resource: resource, level: level, haveBytes: have, needBytes: need)
    }
}
