import Foundation

/// Settings of the hub's own players, by id.
public struct AudioHubSources: Equatable, Sendable {
    public static let path = "/gryonixnexus/settings"

    public var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    /// Reads the agent's JSON object of strings
    public init(json: String) {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        values = object ?? [:]
    }

    public var hasSpotify: Bool { values["spotify.name"] != nil }
    public var hasAirPlay: Bool { values["airplay.name"] != nil }
    public var hasLibrary: Bool { values["mpd.name"] != nil }
    public var isEmpty: Bool { values.isEmpty }

    /// The edited values as JSON, nil when nothing differs
    public func changes(from saved: AudioHubSources) -> String? {
        let changed = values.filter { saved.values[$0.key] != $0.value }
        guard !changed.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
