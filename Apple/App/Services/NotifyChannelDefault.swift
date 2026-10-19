import AgentClient
import Foundation

/// Where every server sends alerts, unless it keeps its own
struct NotifyChannelDefault: Equatable {
    var channel: Gryonixnexusd_V1_NotifyChannel = .relay
    var relayURL = NotifyDraft.defaultRelayURL
    var ntfyURL = "https://ntfy.sh"
    var ntfyTopic = ""

    enum Key {
        static let channel = "notify.channel"
        static let relayURL = "notify.relayURL"
        static let ntfyURL = "notify.ntfyURL"
        static let ntfyTopic = "notify.ntfyTopic"
    }

    static func current(_ defaults: UserDefaults = .standard) -> NotifyChannelDefault {
        var choice = NotifyChannelDefault()
        choice.channel = channel(named: defaults.string(forKey: Key.channel))
        choice.relayURL = nonEmpty(defaults.string(forKey: Key.relayURL)) ?? choice.relayURL
        choice.ntfyURL = nonEmpty(defaults.string(forKey: Key.ntfyURL)) ?? choice.ntfyURL
        choice.ntfyTopic = nonEmpty(defaults.string(forKey: Key.ntfyTopic)) ?? NotifyDraft.randomTopic()
        if defaults.string(forKey: Key.ntfyTopic) == nil { defaults.set(choice.ntfyTopic, forKey: Key.ntfyTopic) }
        return choice
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(Self.name(of: channel), forKey: Key.channel)
        defaults.set(relayURL.trimmingCharacters(in: .whitespaces), forKey: Key.relayURL)
        defaults.set(ntfyURL.trimmingCharacters(in: .whitespaces), forKey: Key.ntfyURL)
        defaults.set(ntfyTopic.trimmingCharacters(in: .whitespaces), forKey: Key.ntfyTopic)
    }

    /// A fingerprint to tell whether a server is in step
    var fingerprint: String { [Self.name(of: channel), relayURL, ntfyURL, ntfyTopic].joined(separator: "|") }

    /// Whether a server already sends this way
    func matches(_ settings: Gryonixnexusd_V1_NotifySettings) -> Bool {
        switch channel {
        case .relay: return settings.channel == .relay && settings.relayURL == relayURL
        case .ntfy: return settings.channel == .ntfy && settings.ntfyURL == ntfyURL && settings.ntfyTopic == ntfyTopic
        default: return settings.channel == .off || settings.channel == .unspecified
        }
    }

    /// The request, sending this way
    func applied(to request: Gryonixnexusd_V1_SetNotifySettingsRequest) -> Gryonixnexusd_V1_SetNotifySettingsRequest {
        var request = request
        request.channel = channel == .unspecified ? .off : channel
        request.relayURL = relayURL
        request.ntfyURL = ntfyURL
        request.ntfyTopic = ntfyTopic
        return request
    }

    // MARK: - A server's own choice

    static func ownKey(for deploymentID: UUID) -> String { "notify.ownChannel.\(deploymentID)" }

    /// Whether a server keeps its own channel, decided once
    static func keepsOwn(_ settings: Gryonixnexusd_V1_NotifySettings, deploymentID: UUID,
                         wanted: NotifyChannelDefault, defaults: UserDefaults = .standard) -> Bool {
        let key = ownKey(for: deploymentID)
        if let stored = defaults.object(forKey: key) as? Bool { return stored }
        let own = !(settings.channel == .off || settings.channel == .unspecified
            || wanted.matches(settings) || isOurRelay(settings))
        defaults.set(own, forKey: key)
        return own
    }

    /// The public relay, on any port
    static func isOurRelay(_ settings: Gryonixnexusd_V1_NotifySettings) -> Bool {
        guard settings.channel == .relay else { return false }
        return URL(string: settings.relayURL)?.host == URL(string: NotifyDraft.defaultRelayURL)?.host
    }

    private static func channel(named name: String?) -> Gryonixnexusd_V1_NotifyChannel {
        switch name {
        case "ntfy": return .ntfy
        case "off": return .off
        default: return .relay
        }
    }

    private static func name(of channel: Gryonixnexusd_V1_NotifyChannel) -> String {
        switch channel {
        case .ntfy: return "ntfy"
        case .relay: return "relay"
        default: return "off"
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return text
    }
}
