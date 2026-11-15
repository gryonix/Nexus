import AudioToolbox
import Foundation
import SwiftUI

/// The kinds of alert a sound can be chosen for
enum NotifySoundGroup: String, CaseIterable, Identifiable {
    case disks, services, backups, agent, operations, ssh

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .disks: return "Disks and RAID"
        case .services: return "A service stopped or keeps restarting"
        case .backups: return "A backup failed"
        case .agent: return "A new agent version"
        case .operations: return "A long operation finished"
        case .ssh: return "Someone signed in over SSH"
        }
    }
}

/// A sound this app carries, the system's, or none
enum NotifySound: String, CaseIterable, Identifiable {
    case standard = "default", none, chime, bell, drop, pulse, alarm

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .standard: return "Default"
        case .none: return "No sound"
        case .chime: return "Chime"
        case .bell: return "Bell"
        case .drop: return "Drop"
        case .pulse: return "Pulse"
        case .alarm: return "Alarm"
        }
    }

    /// Plays it once, as a preview
    func play() {
        switch self {
        case .none: return
        case .standard: AudioServicesPlaySystemSound(1007)
        default:
            guard let url = Bundle.main.url(forResource: rawValue, withExtension: "wav") else { return }
            var id: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
            AudioServicesPlaySystemSoundWithCompletion(id) { AudioServicesDisposeSystemSoundID(id) }
        }
    }
}

/// This device's sound per kind of alert
enum NotifySounds {
    static func key(_ group: NotifySoundGroup) -> String { "notify.sound.\(group.rawValue)" }

    static func sound(_ group: NotifySoundGroup, _ defaults: UserDefaults = .standard) -> NotifySound {
        NotifySound(rawValue: defaults.string(forKey: key(group)) ?? "") ?? .standard
    }

    /// Only the kinds that differ from the system sound
    static func chosen(_ defaults: UserDefaults = .standard) -> [String: String] {
        var chosen: [String: String] = [:]
        for group in NotifySoundGroup.allCases where sound(group, defaults) != .standard {
            chosen[group.rawValue] = sound(group, defaults).rawValue
        }
        return chosen
    }

    /// Changes when any choice does
    static func fingerprint(_ defaults: UserDefaults = .standard) -> String {
        chosen(defaults).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}
