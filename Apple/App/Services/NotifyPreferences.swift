import AgentClient
import Foundation

/// What this device wants to hear about, for every server
struct NotifyPreferences: Equatable {
    var disks = true
    var spacePercent = 90
    var services = true
    var backups = true
    var agentUpdate = true
    var appUpdate = true
    var operations = false
    var sshLogins = true
    var unusualLoad = true
    var widgetMinutes = NotifyPreferences.widgetMinuteChoices[2]

    /// How often a server may refresh the widgets
    static let widgetMinuteChoices = [15, 30, 60, 180]

    enum Key {
        static let disks = "notify.disks"
        static let spacePercent = "notify.spacePercent"
        static let services = "notify.services"
        static let backups = "notify.backups"
        static let agentUpdate = "notify.agentUpdate"
        static let appUpdate = "notify.appUpdate"
        static let operations = "notify.operations"
        static let sshLogins = "notify.sshLogins"
        static let unusualLoad = "notify.unusualLoad"
        static let widgetMinutes = "notify.widgetMinutes"
    }

    static let appUpdateTopic = "app_update"

    static func current(_ defaults: UserDefaults = .standard) -> NotifyPreferences {
        func flag(_ key: String, _ fallback: Bool = true) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        let percent = defaults.integer(forKey: Key.spacePercent)
        let minutes = defaults.integer(forKey: Key.widgetMinutes)
        return NotifyPreferences(disks: flag(Key.disks),
                                 spacePercent: (50...99).contains(percent) ? percent : 90,
                                 services: flag(Key.services),
                                 backups: flag(Key.backups),
                                 agentUpdate: flag(Key.agentUpdate),
                                 appUpdate: flag(Key.appUpdate),
                                 operations: flag(Key.operations, false),
                                 sshLogins: flag(Key.sshLogins),
                                 unusualLoad: flag(Key.unusualLoad),
                                 widgetMinutes: widgetMinuteChoices.contains(minutes) ? minutes : 60)
    }

    /// The checks a server runs for these wishes
    var checks: Gryonixnexusd_V1_NotifyChecks {
        var checks = Gryonixnexusd_V1_NotifyChecks()
        checks.raid = disks
        checks.smart = disks
        checks.diskSpace = disks
        checks.diskSpacePercent = UInt32(spacePercent)
        checks.services = services
        checks.backups = backups
        checks.agentUpdate = agentUpdate
        checks.operations = operations
        checks.sshLogins = sshLogins
        checks.unusualLoad = unusualLoad
        checks.widgetRefreshMinutes = UInt32(widgetMinutes)
        return checks
    }

    /// Relay announcements this device turns down
    var muted: [String] { appUpdate ? [] : [Self.appUpdateTopic] }

    /// A fingerprint to tell whether a server is in step
    var fingerprint: String {
        [disks, services, backups, agentUpdate, appUpdate, operations, sshLogins, unusualLoad].map { $0 ? "1" : "0" }.joined() + "\(spacePercent)w\(widgetMinutes)"
    }
}
