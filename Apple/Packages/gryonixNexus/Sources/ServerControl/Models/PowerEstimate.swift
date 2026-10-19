import Foundation

/// One line of the estimate: a part and its watts
public struct PowerPart: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case processor, memory, nvme, ssd, hdd, graphics
        case serverBoard, desktopBoard, compactBoard, singleBoard, virtualShare, powerSupply
    }

    public var kind: Kind
    public var name: String
    public var count: Int
    public var idleWatts: Double
    public var peakWatts: Double

    public init(_ kind: Kind, name: String = "", count: Int = 1, idle: Double, peak: Double) {
        self.kind = kind
        self.name = name
        self.count = count
        idleWatts = (idle * 10).rounded() / 10
        peakWatts = (peak * 10).rounded() / 10
    }
}

/// Watts a machine likely draws, added up from its parts
public struct PowerEstimate: Codable, Sendable, Hashable {
    public var parts: [PowerPart]
    public var isVirtual: Bool
    public var detectedAt: Date

    public var profile: EnergyProfile {
        EnergyProfile(idleWatts: parts.reduce(0) { $0 + $1.idleWatts },
                      peakWatts: parts.reduce(0) { $0 + $1.peakWatts })
    }

    /// Part kinds a partial sensor already measures
    static func covered(by source: String) -> Set<PowerPart.Kind>? {
        switch source {
        case "rapl", "hwmon": return [.processor, .virtualShare]
        case "pi": return [.singleBoard]
        default: return nil
        }
    }

    /// Watts of the parts a partial sensor does not see
    public func unseenWatts(source: String, measured: Double, cpuPercent: Double?) -> Double {
        guard let covered = Self.covered(by: source) else { return 0 }
        let load = min(max(cpuPercent ?? 0, 0), 100) / 100
        let own = parts.filter { $0.kind != .powerSupply }
        let others = own.filter { !covered.contains($0.kind) }
            .reduce(0) { $0 + $1.idleWatts + ($1.peakWatts - $1.idleWatts) * load }
        let ownIdle = own.reduce(0) { $0 + $1.idleWatts }
        let supplyIdle = parts.first { $0.kind == .powerSupply }?.idleWatts ?? 0
        let losses = ownIdle > 0 ? supplyIdle / ownIdle : 0
        return others + (measured + others) * losses
    }

    public init(_ hardware: PowerHardware, at date: Date = Date()) {
        isVirtual = hardware.isVirtual
        detectedAt = date
        if hardware.isVirtual {
            parts = Self.virtualParts(hardware)
        } else if let board = SingleBoard.figures(hardware) {
            parts = [board] + Self.diskParts(hardware)
            parts.append(Self.losses(parts, efficiency: 0.85))
        } else {
            parts = Self.machineParts(hardware)
        }
    }

    private static func virtualParts(_ hardware: PowerHardware) -> [PowerPart] {
        let threads = max(hardware.threads, 1)
        return [PowerPart(.virtualShare, count: threads, idle: 2 * Double(threads), peak: 7 * Double(threads)),
                memory(hardware.memoryBytes)]
    }

    private static func machineParts(_ hardware: PowerHardware) -> [PowerPart] {
        let cpu = ProcessorPower.figures(model: hardware.processor, cores: hardware.coresPerSocket)
        let sockets = Double(hardware.sockets)
        let platform = platform(hardware, cpu: cpu.platform)
        var parts = [
            PowerPart(.processor, name: ProcessorPower.normalized(hardware.processor), count: hardware.sockets,
                      idle: cpu.idle * sockets, peak: cpu.peak * sockets),
            board(platform, sockets: hardware.sockets),
            memory(hardware.memoryBytes),
        ] + diskParts(hardware)
        if hardware.graphics > 0 {
            let cards = Double(hardware.graphics)
            parts.append(PowerPart(.graphics, count: hardware.graphics, idle: 12 * cards, peak: 15 * cards))
        }
        let efficiency = platform == .server ? 0.9 : platform == .desktop ? 0.87 : 0.85
        parts.append(losses(parts, efficiency: efficiency))
        return parts
    }

    private static let serverChassis: Set = [17, 23, 25, 28, 29]
    private static let compactChassis: Set = [8, 9, 10, 13, 14, 30, 31, 32, 35, 36]

    private static func platform(_ hardware: PowerHardware,
                                 cpu: ProcessorPower.Platform) -> ProcessorPower.Platform {
        if serverChassis.contains(hardware.chassis) || hardware.sockets > 1 { return .server }
        if compactChassis.contains(hardware.chassis) { return .compact }
        return cpu
    }

    private static func board(_ platform: ProcessorPower.Platform, sockets: Int) -> PowerPart {
        switch platform {
        case .server:
            let idle = 30 + 15 * Double(sockets - 1)
            return PowerPart(.serverBoard, idle: idle, peak: idle + 25)
        case .desktop: return PowerPart(.desktopBoard, idle: 10, peak: 15)
        case .compact: return PowerPart(.compactBoard, idle: 3, peak: 6)
        }
    }

    private static func memory(_ bytes: Int64) -> PowerPart {
        let gigabytes = Double(bytes) / 1_073_741_824
        return PowerPart(.memory, count: Int(gigabytes.rounded()),
                         idle: max(0.08 * gigabytes, 1), peak: max(0.2 * gigabytes, 1.5))
    }

    private static func diskParts(_ hardware: PowerHardware) -> [PowerPart] {
        [(PowerPart.Kind.nvme, hardware.nvme, 2.0, 6.0),
         (.ssd, hardware.ssd, 0.5, 3.0),
         (.hdd, hardware.hdd, 5.0, 8.0)]
            .filter { $0.1 > 0 }
            .map { PowerPart($0.0, count: $0.1, idle: $0.2 * Double($0.1), peak: $0.3 * Double($0.1)) }
    }

    /// Watts the power supply turns into heat
    private static func losses(_ parts: [PowerPart], efficiency: Double) -> PowerPart {
        let extra = 1 / efficiency - 1
        return PowerPart(.powerSupply, idle: parts.reduce(0) { $0 + $1.idleWatts } * extra,
                         peak: parts.reduce(0) { $0 + $1.peakWatts } * extra)
    }
}

/// Whole-board watts for single-board computers
enum SingleBoard {
    private static let boards: [(pattern: String, idle: Double, peak: Double)] = [
        ("Raspberry Pi 5", 2.7, 7.5),
        ("Raspberry Pi Compute Module 4", 2.0, 5.5),
        ("Raspberry Pi (4|400)", 2.7, 6.4),
        ("Raspberry Pi 3", 1.9, 5.1),
        ("Raspberry Pi Zero 2", 0.6, 3.0),
        ("Raspberry Pi Zero", 0.5, 1.2),
        ("Raspberry Pi", 1.4, 3.5),
    ]

    static func figures(_ hardware: PowerHardware) -> PowerPart? {
        if let known = boards.first(where: {
            hardware.board.range(of: $0.pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return PowerPart(.singleBoard, name: hardware.board, idle: known.idle, peak: known.peak)
        }
        let armBoard = hardware.chassis == 0 && !hardware.board.isEmpty
            && hardware.processor.range(of: "Cortex|ARMv", options: .caseInsensitive) != nil
        return armBoard ? PowerPart(.singleBoard, name: hardware.board, idle: 2.5, peak: 8) : nil
    }
}
