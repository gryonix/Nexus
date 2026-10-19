import SwiftUI
import VPNTunnel
import WidgetKit

struct FleetStatusCard: View {
    let verdict: FleetPresentation.Verdict
    let title: LocalizedStringKey
    let headline: String
    var detail: String?
    var age: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: FleetPresentation.symbol(verdict))
                    .foregroundStyle(FleetPresentation.tint(verdict))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(verbatim: headline)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            if let detail {
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let age {
                Text(verbatim: age)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// What a widget says when it has been given nothing
struct FleetUnavailableCard: View {
    let title: LocalizedStringKey
    let available: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "server.rack")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(available ? "Nothing read yet" : "Open gryonixNexus")
                .font(.footnote)
            Text(available
                 ? "Open a server once and this fills in."
                 : "This build cannot share readings with its widgets yet.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - The four

struct FleetHealthWidgetView: View {
    let entry: FleetEntry

    var body: some View {
        let snapshot = entry.snapshot
        if let snapshot, !snapshot.serversWithServiceReadings.isEmpty {
            FleetStatusCard(
                verdict: FleetPresentation.fleetVerdict(snapshot),
                title: "Fleet",
                headline: snapshot.servicesNeedingAttention == 0
                    ? String(localized: "All well")
                    : String(localized: "\(snapshot.servicesNeedingAttention) need attention"),
                detail: detail(snapshot),
                age: FleetPresentation.age(snapshot.oldestReadingAge))
        } else {
            FleetUnavailableCard(title: "Fleet", available: entry.available)
        }
    }

    private func detail(_ snapshot: FleetSnapshot) -> String {
        var parts = [String(localized: "\(snapshot.totalServices) services on \(snapshot.serversWithServiceReadings.count) servers")]
        if snapshot.unreachableServerCount > 0 {
            parts.append(String(localized: "\(snapshot.unreachableServerCount) unreachable"))
        }
        return parts.joined(separator: " · ")
    }
}

struct SecurityWidgetView: View {
    let entry: ServerSectionEntry

    var body: some View {
        if let server = entry.server, let security = server.security {
            FleetStatusCard(
                verdict: FleetPresentation.securityVerdict(security),
                title: "Security",
                headline: security.isPresent
                    ? String(localized: "\(security.alertsLast24h) attacks today")
                    : String(localized: "Not set up"),
                detail: detail(security, server: server),
                age: FleetPresentation.age(security.age))
        } else {
            FleetUnavailableCard(title: "Security", available: entry.available)
        }
    }

    private func detail(_ security: FleetSnapshot.SecuritySummary,
                        server: FleetSnapshot.Server) -> String {
        guard security.isPresent else { return server.name }
        if !security.isGuarding {
            return String(localized: "Installed but not blocking")
        }
        return String(localized: "\(security.localBans) banned · \(server.name)")
    }
}

struct BackupsWidgetView: View {
    let entry: ServerSectionEntry

    var body: some View {
        if let server = entry.server, let backups = server.backups {
            FleetStatusCard(
                verdict: FleetPresentation.backupsVerdict(backups),
                title: "Backups",
                headline: FleetPresentation.cadence(backups),
                detail: detail(backups, server: server),
                age: FleetPresentation.age(backups.age))
        } else {
            FleetUnavailableCard(title: "Backups", available: entry.available)
        }
    }

    private func detail(_ backups: FleetSnapshot.BackupsSummary,
                        server: FleetSnapshot.Server) -> String {
        guard backups.isOn else { return String(localized: "Nothing is backed up automatically") }
        guard backups.servicesCovered > 0 else {
            return String(localized: "Scheduled, but no services chosen")
        }
        return String(localized: "\(backups.servicesCovered) services · keeps \(backups.retention)")
    }
}

struct UpdatesWidgetView: View {
    let entry: ServerSectionEntry

    var body: some View {
        if let server = entry.server, let updates = server.updates {
            FleetStatusCard(
                verdict: FleetPresentation.updatesVerdict(updates),
                title: "Updates",
                headline: updates.waiting == 0
                    ? String(localized: "Up to date")
                    : String(localized: "\(updates.waiting) waiting"),
                detail: String(localized: "\(updates.checked) checked · \(server.name)"),
                age: FleetPresentation.age(updates.age))
        } else {
            FleetUnavailableCard(title: "Updates", available: entry.available)
        }
    }
}

// MARK: - Entries

struct FleetEntry: TimelineEntry {
    let date: Date
    let snapshot: FleetSnapshot?
    let available: Bool
}

/// One server, for the three widgets that are about one
struct ServerSectionEntry: TimelineEntry {
    let date: Date
    let server: FleetSnapshot.Server?
    let available: Bool
}
