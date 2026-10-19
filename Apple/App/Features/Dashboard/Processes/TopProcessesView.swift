import ServerControl
import SwiftUI

/// What uses the most processor or memory on one machine
struct TopProcessesView: View {
    @StateObject private var model: TopProcessesModel
    @AppStorage("processes.friendlyNames") private var friendly = true
    @AppStorage("processes.byMemory") private var byMemory = false

    init(target: TopProcessesTarget) {
        _model = StateObject(wrappedValue: TopProcessesModel(target: target))
    }

    private var rows: [ProcessRow] {
        TopProcesses.rows(model.samples, friendly: friendly, byMemory: byMemory)
    }

    var body: some View {
        Form {
            Section {
                Picker("Sort by", selection: $byMemory) {
                    Text("CPU").tag(false)
                    Text("Memory").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Friendly names", isOn: $friendly)
            } footer: {
                Text("Friendly names group each program under a name you know; off shows what the system calls them.")
            }
            ProcessListSection(rows: rows, loaded: model.loaded, error: model.errorMessage)
        }
        .navigationTitle("Top processes")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.follow() }
    }
}

/// The ranked processes, or why there are none
private struct ProcessListSection: View {
    let rows: [ProcessRow]
    let loaded: Bool
    let error: String?

    var body: some View {
        Section {
            if !loaded {
                HStack { ProgressView().controlSize(.small); Text("Reading processes…") }
            }
            ForEach(rows) { ProcessRowView(row: $0) }
            if let error { Text(verbatim: error).foregroundStyle(.red) }
        } footer: {
            Text("Updates every 5 seconds.")
        }
    }
}

private struct ProcessRowView: View {
    let row: ProcessRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.count > 1 ? "\(row.name) ×\(row.count)" : row.name)
                if !row.detail.isEmpty {
                    Text(verbatim: row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: String(format: "%.1f %%", row.cpu)).monospacedDigit()
                Text(verbatim: ByteCountFormatter.string(fromByteCount: row.memoryKiB * 1024, countStyle: .memory))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
