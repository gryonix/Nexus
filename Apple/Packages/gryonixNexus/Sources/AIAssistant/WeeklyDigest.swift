import Foundation

public struct AIUsageSample: Equatable, Sendable {
    public var time: Date
    public var cpuPercent: Double?
    public var memoryFraction: Double?
    public var diskFraction: Double?
    public var temperature: Double?

    public init(time: Date, cpuPercent: Double?, memoryFraction: Double?,
                diskFraction: Double?, temperature: Double?) {
        self.time = time
        self.cpuPercent = cpuPercent
        self.memoryFraction = memoryFraction
        self.diskFraction = diskFraction
        self.temperature = temperature
    }
}

/// Turns a week of samples into model text.
public enum AIWeeklyDigest {
    public static func lines(server: String, samples: [AIUsageSample]) -> String {
        guard !samples.isEmpty else { return "\(server): no history" }
        let sorted = samples.sorted { $0.time < $1.time }
        var parts = ["\(server): \(sorted.count) samples"]
        if let cpu = stat(sorted.compactMap(\.cpuPercent)) {
            parts.append(String(format: "CPU avg %.0f%% max %.0f%%", cpu.avg, cpu.max))
        }
        if let mem = stat(sorted.compactMap(\.memoryFraction)) {
            parts.append(String(format: "memory avg %.0f%% max %.0f%%", mem.avg * 100, mem.max * 100))
        }
        if let first = sorted.compactMap(\.diskFraction).first, let last = sorted.compactMap(\.diskFraction).last {
            parts.append(String(format: "disk %.0f%% -> %.0f%%", first * 100, last * 100))
        }
        if let temp = stat(sorted.compactMap(\.temperature)) {
            parts.append(String(format: "temperature max %.0f C", temp.max))
        }
        return parts.joined(separator: ", ")
    }

    private static func stat(_ values: [Double]) -> (avg: Double, max: Double)? {
        guard let peak = values.max() else { return nil }
        return (values.reduce(0, +) / Double(values.count), peak)
    }
}
