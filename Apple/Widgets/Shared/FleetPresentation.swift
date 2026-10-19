import SwiftUI
import VPNTunnel

/// The words and colours the four fleet widgets share
enum FleetPresentation {
    enum Verdict: Equatable {
        /// Answered, and the answer is good
        case well
        /// Answered, and something wants a person
        case attention
        /// Answered, and it is bad
        case bad
        /// Not answered
        case unknown
    }

    static func symbol(_ verdict: Verdict) -> String {
        switch verdict {
        case .well: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    static func tint(_ verdict: Verdict) -> Color {
        switch verdict {
        case .well: return .green
        case .attention: return .orange
        case .bad: return .red
        case .unknown: return .secondary
        }
    }

    // MARK: - The four verdicts

    static func fleetVerdict(_ snapshot: FleetSnapshot) -> Verdict {
        guard !snapshot.serversWithServiceReadings.isEmpty else { return .unknown }
        if snapshot.unreachableServerCount > 0 { return .bad }
        return snapshot.servicesNeedingAttention > 0 ? .attention : .well
    }

    static func securityVerdict(_ summary: FleetSnapshot.SecuritySummary?) -> Verdict {
        guard let summary else { return .unknown }
        guard summary.isPresent else { return .attention }
        return summary.isGuarding ? .well : .bad
    }

    static func backupsVerdict(_ summary: FleetSnapshot.BackupsSummary?) -> Verdict {
        guard let summary else { return .unknown }
        guard summary.isOn else { return .attention }
        return summary.servicesCovered > 0 ? .well : .attention
    }

    static func updatesVerdict(_ summary: FleetSnapshot.UpdatesSummary?) -> Verdict {
        guard let summary else { return .unknown }
        return summary.waiting > 0 ? .attention : .well
    }

    // MARK: - Words

    /// How old a reading is
    static func age(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        return ServerMetricsPresentation.age(seconds)
    }

    static func cadence(_ summary: FleetSnapshot.BackupsSummary) -> String {
        guard summary.isOn else { return String(localized: "Off") }
        if let hours = summary.everyHours {
            return hours == 1 ? String(localized: "Hourly")
                              : String(localized: "Every \(hours) hours")
        }
        if let days = summary.everyDays {
            return days == 1 ? String(localized: "Daily")
                             : String(localized: "Every \(days) days")
        }
        return String(localized: "On")
    }
}
