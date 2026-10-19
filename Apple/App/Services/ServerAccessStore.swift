import Foundation
import ServerControl

/// Where `ServerAccessOptions` live: this device's defaults, keyed by deployment
enum ServerAccessStore {
    private static let prefix = "server-access-"

    private static func key(_ deploymentID: UUID) -> String {
        prefix + deploymentID.uuidString
    }

    static func options(for deploymentID: UUID,
                        defaults: UserDefaults = .standard) -> ServerAccessOptions {
        guard let data = defaults.data(forKey: key(deploymentID)),
              let options = try? JSONDecoder().decode(ServerAccessOptions.self, from: data)
        else { return .none }
        return options
    }

    static func save(_ options: ServerAccessOptions, for deploymentID: UUID,
                     defaults: UserDefaults = .standard) {
        guard !options.isEmpty else {
            defaults.removeObject(forKey: key(deploymentID))
            return
        }
        guard let data = try? JSONEncoder().encode(options) else { return }
        defaults.set(data, forKey: key(deploymentID))
    }

    /// Forget a server's route along with the server
    static func forget(_ deploymentID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(deploymentID))
    }
}
