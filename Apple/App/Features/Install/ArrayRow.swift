import ServiceCatalog
import SwiftUI

/// One array: its name, level, members and health
struct ArrayRow: View {
    let array: StorageArray

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(verbatim: title).font(.body)
            }
            Text(verbatim: members)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state)
                .font(.caption)
                .foregroundStyle(tint)
        }
    }

    private var title: String {
        [array.name, array.level.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var members: String {
        let working = array.members.map { $0.replacingOccurrences(of: "/dev/", with: "") }
        let failed = array.failed.map { $0.replacingOccurrences(of: "/dev/", with: "") + " ✕" }
        let spares = array.spares.map { UIL10n.string("%@ (spare)", $0.replacingOccurrences(of: "/dev/", with: "")) }
        return (working + failed + spares).joined(separator: ", ")
            + (array.mountpoint.map { " → " + $0 } ?? "")
    }

    private var state: LocalizedStringKey {
        if array.isForeignSystemPool { return "System pool of an earlier TrueNAS: left alone" }
        switch array.state {
        case .clean: return "Healthy"
        case .degraded: return "Degraded: \(array.working) of \(array.slots) disks work"
        case .rebuilding(let percent): return "Rebuilding: \(Int(percent))%"
        case .checking(let percent): return "Checking: \(Int(percent))%"
        case .stopped: return "Not running — found on the disks"
        case .unknown:
            return array.kind == .hardware ? "Health is kept by the RAID controller"
                : "Health unknown: this account cannot read it"
        }
    }

    private var symbol: String {
        switch array.state {
        case .clean: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .rebuilding: return "arrow.triangle.2.circlepath"
        case .checking: return "magnifyingglass"
        case .stopped: return "pause.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch array.state {
        case .clean: return .green
        case .degraded: return .red
        case .rebuilding: return .orange
        case .checking: return .blue
        case .stopped, .unknown: return .secondary
        }
    }
}
