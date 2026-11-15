import Foundation

/// The audio hub as odio-api reports it.
public struct AudioHubState: Equatable, Sendable {
    public struct Output: Equatable, Sendable, Identifiable {
        public let name: String
        public let title: String
        public let volume: Double
        public let muted: Bool
        public let isDefault: Bool
        public var id: String { name }
    }

    public struct Player: Equatable, Sendable, Identifiable {
        public let busName: String
        public let identity: String
        public let status: String
        public let title: String
        public let artist: String
        public let canGoNext: Bool
        public let canGoPrevious: Bool
        public var id: String { busName }
        public var isPlaying: Bool { status == "Playing" }
    }

    public struct Service: Equatable, Sendable, Identifiable {
        public let unit: String
        public let title: String
        public let running: Bool
        public var id: String { unit }
    }

    public var volume: Double = 0
    public var muted = false
    public var outputs: [Output] = []
    public var players: [Player] = []
    public var services: [Service] = []
    public var bluetoothPowered = false
    public var bluetoothPairing = false

    public init() {}

    /// Players the hub can switch on and off
    public static let switchableUnits = [
        "spotifyd.service", "shairport-sync.service", "mpd.service", "snapclient.service", "upmpdcli.service"
    ]

    public static func percent(_ volume: Double) -> Int { Int((volume * 100).rounded()) }
}

/// Builds `AudioHubState` from odio-api JSON bodies
public enum AudioHubParser {
    public static func apply(server body: String, to state: inout AudioHubState) {
        guard let object = json(body) as? [String: Any] else { return }
        state.volume = number(object["volume"])
        state.muted = object["muted"] as? Bool ?? false
    }

    public static func outputs(_ body: String) -> [AudioHubState.Output] {
        (json(body) as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let title = (item["description"] as? String) ?? (item["nick"] as? String) ?? name
            return AudioHubState.Output(name: name, title: title, volume: number(item["volume"]),
                                        muted: item["muted"] as? Bool ?? false,
                                        isDefault: item["default"] as? Bool ?? false)
        }
    }

    public static func players(_ body: String) -> [AudioHubState.Player] {
        (json(body) as? [[String: Any]] ?? []).compactMap { item in
            guard let bus = item["bus_name"] as? String else { return nil }
            let metadata = item["metadata"] as? [String: Any] ?? [:]
            let caps = item["capabilities"] as? [String: Any] ?? [:]
            let artist = (metadata["xesam:artist"] as? String)
                ?? (metadata["xesam:artist"] as? [String] ?? []).joined(separator: ", ")
            return AudioHubState.Player(
                busName: bus, identity: item["identity"] as? String ?? bus,
                status: item["playback_status"] as? String ?? "",
                title: metadata["xesam:title"] as? String ?? "", artist: artist,
                canGoNext: caps["can_go_next"] as? Bool ?? false,
                canGoPrevious: caps["can_go_previous"] as? Bool ?? false)
        }
    }

    public static func services(_ body: String) -> [AudioHubState.Service] {
        (json(body) as? [[String: Any]] ?? []).compactMap { item in
            guard let unit = item["name"] as? String, item["scope"] as? String == "user",
                  AudioHubState.switchableUnits.contains(unit), item["exists"] as? Bool ?? true
            else { return nil }
            return AudioHubState.Service(unit: unit, title: item["description"] as? String ?? unit,
                                         running: item["running"] as? Bool ?? false)
        }
    }

    public static func apply(bluetooth body: String, to state: inout AudioHubState) {
        guard let object = json(body) as? [String: Any] else { return }
        state.bluetoothPowered = object["powered"] as? Bool ?? false
        state.bluetoothPairing = object["pairing_active"] as? Bool ?? false
    }

    /// JSON body for a volume between 0 and 1
    public static func volumeBody(_ volume: Double) -> String {
        "{\"volume\":\(String(format: "%.2f", min(max(volume, 0), 1)))}"
    }

    private static func json(_ body: String) -> Any? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }
}
