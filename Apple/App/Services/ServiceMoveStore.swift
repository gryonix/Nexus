import Foundation
import ServerControl

struct ServiceMoveStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ deployment: UUID) -> String { "service-move-\(deployment.uuidString)" }

    func record(for deployment: UUID) -> ServiceMoveRecord? {
        defaults.data(forKey: key(deployment)).flatMap { try? JSONDecoder().decode(ServiceMoveRecord.self, from: $0) }
    }

    func save(_ record: ServiceMoveRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key(record.deployment))
    }

    func clear(deployment: UUID) {
        defaults.removeObject(forKey: key(deployment))
    }
}
