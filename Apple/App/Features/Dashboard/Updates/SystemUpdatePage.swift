import ServerControl
import ServiceCatalog
import SwiftUI

/// Server packages: now, by schedule, at start or stop
struct SystemUpdatePage: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var model: SystemUpdateModel

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _model = StateObject(wrappedValue: SystemUpdateModel(isDemo: DemoFleet.covers(viewModel.deployment),
                                                             serverName: viewModel.deployment.name,
                                                             session: { [viewModel] in
            try await viewModel.commandSession()
        }))
    }

    private var hosts: [SSHHostID] { viewModel.deployment.nodes.map(\.sshHost) }

    var body: some View {
        CardList {
            ForEach(hosts, id: \.self) { host in
                Section {
                    SystemUpdateRows(model: model, host: host, hosts: hosts)
                } header: {
                    if let label = viewModel.deployment.metricsMachineLabel(for: host) {
                        Text(verbatim: label)
                    }
                } footer: {
                    Text("For a server that is not on all the time: it updates as it starts or before it shuts down. A restart counts as both. The apps are the ones chosen under Updates.")
                }
                Section {
                    SystemScheduleRows(model: model, host: host)
                }
            }
        }
        .navigationTitle(Text("Server system"))
        .raisedNavigationTitle()
        .task { await model.load(hosts) }
    }
}

/// One machine's package updates
private struct SystemUpdateRows: View {
    @ObservedObject var model: SystemUpdateModel
    let host: SSHHostID
    let hosts: [SSHHostID]

    private var status: SystemUpdateStatus? { model.statuses[host] }

    var body: some View {
        if model.missing.contains(host) {
            Text("Update the agent on this server to use this.").foregroundStyle(.secondary)
        } else {
            summary
            updateButton
            if let status, status.isRunning || status.exitCode.map({ $0 != 0 }) == true { SystemUpdateLog(lines: status.log) }
            if status?.needsRestart == true {
                Label("A restart finishes the update.", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.orange)
            }
            SwapControl(model: model, host: host, status: status)
            toggle("Update the system at start", part: .system, isOn: status?.systemAtStart ?? false)
            toggle("Update the apps at start", part: .apps, isOn: status?.appsAtStart ?? false)
            if status?.offersAtStop == true {
                toggle("Update the system at shutdown", part: .system, atStop: true, isOn: status?.systemAtStop ?? false)
                toggle("Update the apps at shutdown", part: .apps, atStop: true, isOn: status?.appsAtStop ?? false)
            }
        }
        if let error = model.errors[host] { Text(verbatim: error).font(.caption).foregroundStyle(.red) }
    }

    @ViewBuilder private var summary: some View {
        if status?.isRunning == true {
            HStack { ProgressView().controlSize(.small); Text("Updating the system…") }
        } else if let code = status?.exitCode, code != 0 {
            Text("The last update failed. See the log below.").foregroundStyle(.red)
        } else if let finished = status?.finished, status?.exitCode != nil {
            Text("Last update: \(finished.formatted(date: .abbreviated, time: .shortened))")
                .foregroundStyle(.secondary)
        } else if status != nil {
            Text("Not updated from the app yet.").foregroundStyle(.secondary)
        }
    }

    private var updateButton: some View {
        Button {
            Task { await model.start(host, among: hosts) }
        } label: {
            Label("Update the system", systemImage: "arrow.down.circle")
        }
        .disabled(status == nil || status?.isRunning == true || model.busy.contains(host))
        .infoNote("Update the system", "Updates the server's own packages. Services keep running; a few may restart.")
    }

    private func toggle(_ title: LocalizedStringKey, part: SystemUpdate.Part, atStop: Bool = false,
                        isOn: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { value in
            Task {
                if atStop {
                    await model.setAtStop(part, on: value, host: host)
                } else {
                    await model.setAtStart(part, on: value, host: host)
                }
            }
        }))
        .disabled(status == nil || model.busy.contains(host))
    }
}

/// The system's own update timer on one machine
private struct SystemScheduleRows: View {
    @ObservedObject var model: SystemUpdateModel
    let host: SSHHostID
    @State private var draft: CommandCatalog.Backups.Schedule?

    private var status: SystemUpdateStatus? { model.statuses[host] }

    var body: some View {
        if let saved = status?.schedule {
            let current = draft ?? saved
            Toggle("Update the system on a schedule", isOn: Binding(
                get: { current.isOn },
                set: { draft = $0 ? ScheduleFields.defaultOn : .off }))
                .disabled(model.busy.contains(host))
            if current.isOn {
                ScheduleFields(schedule: Binding(get: { draft ?? saved }, set: { draft = $0 }))
            }
            if let draft, draft != saved {
                Button("Save schedule") {
                    Task {
                        await model.setSchedule(draft, host: host)
                        self.draft = nil
                    }
                }
                .rowActionButtonStyle()
                .disabled(model.busy.contains(host))
            }
        } else if status != nil {
            Text("Update the agent on this server to update on a schedule.").foregroundStyle(.secondary)
        }
    }
}

/// The last lines the updater wrote
private struct SystemUpdateLog: View {
    let lines: [String]

    var body: some View {
        Text(verbatim: lines.suffix(12).joined(separator: "\n"))
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

/// The machine's swap, and the app's swap file size
private struct SwapControl: View {
    @ObservedObject var model: SystemUpdateModel
    let host: SSHHostID
    let status: SystemUpdateStatus?
    @State private var custom = false

    var body: some View {
        AdaptiveRow("Swap") { _ in
            Menu {
                ForEach([1, 2, 4, 8], id: \.self) { size in
                    Button(UIL10n.string("%@ GB", "\(size)")) { apply(size) }
                }
                Button("Other size…") { custom = true }
                Button("Turn swap off", role: .destructive) { apply(nil) }
                    .dangerTint()
            } label: {
                Text(verbatim: summary)
            }
            .disabled(status == nil || model.busy.contains(host))
        }
        .customSwapSize(isPresented: $custom) { apply($0) }
    }

    private var summary: String {
        guard let status, status.swapBytes > 0 else { return UIL10n.string("None") }
        return ByteCountFormatter.string(fromByteCount: status.swapBytes, countStyle: .memory)
    }

    private func apply(_ size: Int?) {
        Task { await model.setSwap(sizeGB: size, host: host) }
    }
}
