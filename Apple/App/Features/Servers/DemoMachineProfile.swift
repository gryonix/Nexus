import Foundation

struct DemoMachineProfile {
    var cores: Int
    var memTotalBytes: Int64
    var diskTotalBytes: Int64
    var diskUsedFraction: Double
    var cpuBusy: Double
    var cpuSwing: Double
    var memUsedFraction: Double
    var memSwing: Double
    var netReceivedPerSecond: Double
    var netSentPerSecond: Double
    var diskReadPerSecond: Double
    var diskWrittenPerSecond: Double
    var temperatureCelsius: Double?
    var uptimeDays: Double
    var osID: String
    var osPrettyName: String

    private static let gigabyte: Int64 = 1_073_741_824

    static let busyHost = DemoMachineProfile(
        cores: 4,
        memTotalBytes: 8 * gigabyte,
        diskTotalBytes: 160 * gigabyte,
        diskUsedFraction: 0.52,
        cpuBusy: 0.34, cpuSwing: 0.12,
        memUsedFraction: 0.61, memSwing: 0.06,
        netReceivedPerSecond: 1_400_000,
        netSentPerSecond: 520_000,
        diskReadPerSecond: 900_000,
        diskWrittenPerSecond: 2_100_000,
        temperatureCelsius: nil,
        uptimeDays: 47,
        osID: "ubuntu",
        osPrettyName: "Ubuntu 24.04 LTS")

    /// Scenario B's relay
    static let relay = DemoMachineProfile(
        cores: 1,
        memTotalBytes: gigabyte,
        diskTotalBytes: 20 * gigabyte,
        diskUsedFraction: 0.27,
        cpuBusy: 0.07, cpuSwing: 0.05,
        memUsedFraction: 0.38, memSwing: 0.04,
        netReceivedPerSecond: 3_600_000,
        netSentPerSecond: 3_400_000,
        diskReadPerSecond: 40_000,
        diskWrittenPerSecond: 120_000,
        temperatureCelsius: nil,
        uptimeDays: 132,
        osID: "debian",
        osPrettyName: "Debian GNU/Linux 12")

    static let homeBackend = DemoMachineProfile(
        cores: 6,
        memTotalBytes: 16 * gigabyte,
        diskTotalBytes: 1000 * gigabyte,
        diskUsedFraction: 0.58,
        cpuBusy: 0.23, cpuSwing: 0.14,
        memUsedFraction: 0.49, memSwing: 0.07,
        // Mirrors the relay's traffic, because it IS the relay's traffic.
        netReceivedPerSecond: 3_100_000,
        netSentPerSecond: 2_800_000,
        diskReadPerSecond: 5_600_000,
        diskWrittenPerSecond: 3_400_000,
        temperatureCelsius: 54,
        uptimeDays: 23,
        osID: "debian",
        osPrettyName: "Debian GNU/Linux 12")

    /// The local-only box: files, photos and media
    static let mediaVault = DemoMachineProfile(
        cores: 4,
        memTotalBytes: 8 * gigabyte,
        diskTotalBytes: 4000 * gigabyte,
        diskUsedFraction: 0.78,
        cpuBusy: 0.16, cpuSwing: 0.20,
        memUsedFraction: 0.44, memSwing: 0.05,
        netReceivedPerSecond: 260_000,
        netSentPerSecond: 6_200_000,
        diskReadPerSecond: 11_000_000,
        diskWrittenPerSecond: 700_000,
        temperatureCelsius: 47,
        uptimeDays: 96,
        osID: "raspbian",
        osPrettyName: "Raspberry Pi OS")

    static let smallLab = DemoMachineProfile(
        cores: 2,
        memTotalBytes: 4 * gigabyte,
        diskTotalBytes: 80 * gigabyte,
        diskUsedFraction: 0.31,
        cpuBusy: 0.11, cpuSwing: 0.07,
        memUsedFraction: 0.52, memSwing: 0.05,
        netReceivedPerSecond: 180_000,
        netSentPerSecond: 90_000,
        diskReadPerSecond: 300_000,
        diskWrittenPerSecond: 400_000,
        temperatureCelsius: nil,
        uptimeDays: 9,
        osID: "ubuntu",
        osPrettyName: "Ubuntu 24.04 LTS")

    static func derived(seed: UInt64) -> DemoMachineProfile {
        func fraction(_ salt: UInt64) -> Double {
            Double((seed &* 6364136223846793005 &+ salt &* 1442695040888963407) % 1000) / 1000
        }
        return DemoMachineProfile(
            cores: [1, 2, 2, 4][Int(seed % 4)],
            memTotalBytes: Int64([420, 964, 2048, 4096][Int(seed % 4)]) * 1_048_576,
            diskTotalBytes: Int64([42, 63, 110, 220][Int(seed % 4)]) * gigabyte,
            diskUsedFraction: 0.1 + fraction(10) * 0.8,
            cpuBusy: 0.05 + fraction(1) * 0.35,
            cpuSwing: 0.08,
            memUsedFraction: 0.35 + fraction(2) * 0.35,
            memSwing: 0.05,
            netReceivedPerSecond: 5_000 + 200_000 * fraction(12),
            netSentPerSecond: 2_000 + 900_000 * fraction(13),
            diskReadPerSecond: 4_000_000 * fraction(14),
            diskWrittenPerSecond: 120_000 * fraction(15),
            temperatureCelsius: seed % 3 == 0 ? 38 + fraction(11) * 20 : nil,
            uptimeDays: Double(seed % 900) / 8.64,
            osID: ["debian", "ubuntu", "raspbian", "fedora"][Int(seed % 4)],
            osPrettyName: "Demo Linux")
    }
}
