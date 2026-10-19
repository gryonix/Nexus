import Foundation
import ServerControl
import ServiceCatalog

/// One finished speed test
struct SpeedRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    let date: Date
    /// Folder tested, or nil for the internet
    let location: String?
    var disk: SpeedTest.DiskResult?
    var internet: SpeedTest.InternetResult?
}

/// Latest speed tests per server, kept on this device
@MainActor
final class SpeedTestHistory: ObservableObject {
    static let shared = SpeedTestHistory()
    static let limit = 20
    private static let key = "speedTest.history"

    private let defaults: UserDefaults
    @Published private var records: [String: [SpeedRecord]] {
        didSet {
            if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.key) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: [SpeedRecord]].self, from: $0) } ?? [:]
    }

    func records(_ deploymentID: UUID, _ host: SSHHostID) -> [SpeedRecord] {
        records[EnergySettings.key(deploymentID, host)] ?? []
    }

    func add(_ record: SpeedRecord, _ deploymentID: UUID, _ host: SSHHostID) {
        let key = EnergySettings.key(deploymentID, host)
        records[key] = Array(([record] + (records[key] ?? [])).prefix(Self.limit))
    }
}
