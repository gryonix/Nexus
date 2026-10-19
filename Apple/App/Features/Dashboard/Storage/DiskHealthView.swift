import ServerControl
import ServiceCatalog
import SwiftUI

/// SMART for every disk, read as root
struct DiskHealthView: View {
    @ObservedObject var model: StorageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var results: [DiskHealth]?

    private var disks: [ServerDisk] { model.hardware?.disks ?? [] }

    var body: some View {
        Form {
            StorageSignInSection(model: model)
            Section {
                Button("Check disk health") { Task { await check() } }
                    .disabled(model.runningStep != nil || disks.isEmpty)
            } footer: {
                if let running = model.runningStep {
                    Label(running, systemImage: "hourglass")
                } else if let failure = model.stepFailure {
                    Text(verbatim: failure).foregroundStyle(.red)
                } else {
                    Text("Reads what each disk reports about itself (SMART). smartmontools is installed on the server if it is missing.")
                }
            }
            if let results {
                Section("Disks") {
                    ForEach(results, id: \.path) { health in
                        DiskHealthRow(health: health, disk: disks.first { $0.path == health.path })
                    }
                }
            }
        }
        .navigationTitle("Disk health")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .task { await model.loadStoredSecret() }
    }

    private func check() async {
        let step = StorageStep.diskHealth(disks.map(\.path))
        guard let output = await model.output(of: step) else { return }
        results = DiskHealth.parse(output)
    }
}

/// One disk's verdict and the figures behind it
private struct DiskHealthRow: View {
    let health: DiskHealth
    let disk: ServerDisk?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(verbatim: disk.map(StorageText.title) ?? health.path)
            }
            Text(verdict).font(.caption).foregroundStyle(tint)
            if !figures.isEmpty {
                Text(verbatim: figures.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var figures: [String] {
        var out: [String] = []
        if let temperature = health.temperature { out.append("\(temperature) °C") }
        if let hours = health.powerOnHours { out.append(UIL10n.string("%lld h on", hours)) }
        if let worn = health.wornPercent { out.append(UIL10n.string("%lld%% worn", worn)) }
        if health.badSectors > 0 { out.append(UIL10n.string("%lld bad sectors", health.badSectors)) }
        return out
    }

    private var verdict: LocalizedStringKey {
        switch health.verdict {
        case .good: return "Healthy"
        case .watch: return "Keep an eye on it: signs of wear"
        case .failing: return "Failing: replace it soon"
        case .unknown: return "No SMART data: the disk or its adapter does not report it"
        }
    }

    private var symbol: String {
        switch health.verdict {
        case .good: return "checkmark.circle.fill"
        case .watch: return "exclamationmark.circle.fill"
        case .failing: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch health.verdict {
        case .good: return .green
        case .watch: return .orange
        case .failing: return .red
        case .unknown: return .secondary
        }
    }
}
