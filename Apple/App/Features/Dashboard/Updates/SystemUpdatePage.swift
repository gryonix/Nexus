import ServerControl
import ServiceCatalog
import SwiftUI

/// Server packages: now, by schedule, at start or stop
struct SystemUpdatePage: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var model: SystemUpdateModel
    #if !os(tvOS)
    @StateObject private var edits = PendingRowEdits()
    #endif

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _model = StateObject(wrappedValue: SystemUpdateModel.make(for: viewModel))
    }

    private var hosts: [SSHHostID] { viewModel.deployment.nodes.map(\.sshHost) }

    var body: some View {
        CardList {
            ForEach(hosts, id: \.self) { host in
                Section {
                    SystemUpdateRows(model: model, host: host, hosts: hosts,
                                     reboot: { await viewModel.rebootHost(host) })
                } header: {
                    if let label = viewModel.deployment.metricsMachineLabel(for: host) {
                        Text(verbatim: label)
                    }
                } footer: {
                    #if !os(tvOS)
                    Text("For a server that is not on all the time: it updates as it starts or before it shuts down. A restart counts as both. The apps are the ones chosen under Updates.")
                    #endif
                }
                #if !os(tvOS)
                Section {
                    SystemScheduleRows(model: model, host: host, edits: edits)
                }
                #endif
            }
        }
        .screenTitle(Text("System update"))
        .raisedNavigationTitle()
        .task { await model.load(hosts) }
        #if !os(tvOS)
        .pendingRowEdits(edits)
        #endif
    }
}

/// One machine's package updates
private struct SystemUpdateRows: View {
    @ObservedObject var model: SystemUpdateModel
    let host: SSHHostID
    let hosts: [SSHHostID]
    let reboot: () async -> Void
    @State private var confirmingReboot = false

    private var status: SystemUpdateStatus? { model.statuses[host] }

    var body: some View {
        if model.missing.contains(host) {
            Text("Update the agent on this server to use this.").foregroundStyle(.secondary)
        } else {
            summary
            updateButton
            if let status, status.isRunning || status.exitCode.map({ $0 != 0 }) == true { SystemUpdateLog(lines: status.log) }
            if status?.needsRestart == true { restartRows }
            #if !os(tvOS)
            toggle("Update the system at start", part: .system, isOn: status?.systemAtStart ?? false)
            if status?.offersAtStop == true {
                toggle("Update the system at shutdown", part: .system, atStop: true, isOn: status?.systemAtStop ?? false)
            }
            toggle("Update the apps at start", part: .apps, isOn: status?.appsAtStart ?? false)
            if status?.offersAtStop == true {
                toggle("Update the apps at shutdown", part: .apps, atStop: true, isOn: status?.appsAtStop ?? false)
            }
            #endif
        }
        if let error = model.errors[host] { Text(verbatim: error).font(.caption).foregroundStyle(.red) }
    }

    /// The notice, and the switch that restarts the machine
    @ViewBuilder private var restartRows: some View {
        Label("A restart finishes the update.", systemImage: "arrow.clockwise.circle")
            .foregroundStyle(.orange)
        Toggle("Reboot to finish updating", isOn: Binding(get: { confirmingReboot },
                                                          set: { if $0 { confirmingReboot = true } }))
            .alert("Reboot this machine?", isPresented: $confirmingReboot) {
                Button("Reboot", role: .destructive) { Task { await reboot() } }
                    .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The machine will go offline for about a minute while it restarts.")
            }
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
    let edits: PendingRowEdits
    @State private var draft: CommandCatalog.Backups.Schedule?

    private var status: SystemUpdateStatus? { model.statuses[host] }

    /// Tells the bar whether the schedule waits
    private func offerEdit() {
        let field = $draft
        let edit = PendingRowEdits.Edit(
            id: "update-schedule-\(host)", text: .schedule,
            apply: { [model, host] in
                if let asked = field.wrappedValue { await model.setSchedule(asked, host: host) }
                field.wrappedValue = nil
                return true
            },
            revert: { field.wrappedValue = nil })
        edits.offer(edit, changed: PendingRules.waits(draft, saved: status?.schedule))
    }

    var body: some View {
        if let saved = status?.schedule {
            let current = draft ?? saved
            Toggle("Update the system on a schedule", isOn: Binding(
                get: { current.isOn },
                set: { draft = $0 ? ScheduleFields.defaultOn : .off }))
                .disabled(model.busy.contains(host))
                .onChange(of: draft) { offerEdit() }
            if current.isOn {
                ScheduleFields(schedule: Binding(get: { draft ?? saved }, set: { draft = $0 }))
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

/// The machine's swap, chosen on a wheel
struct SwapControl: View {
    @ObservedObject var model: SystemUpdateModel
    let host: SSHHostID
    let status: SystemUpdateStatus?
    let edits: PendingRowEdits
    @State private var draft: Int?

    private var savedGB: Int {
        guard let bytes = status?.swapBytes, bytes > 0 else { return 0 }
        return max(1, Int((Double(bytes) / 1_073_741_824).rounded()))
    }

    private var choices: [Int] {
        let current = draft ?? savedGB
        return SwapPlan.wheel.contains(current) ? SwapPlan.wheel : (SwapPlan.wheel + [current]).sorted()
    }

    var body: some View {
        WheelRow(title: "Swap", choices: choices,
                 selection: Binding(get: { draft ?? savedGB }, set: { draft = $0 }),
                 disabled: status == nil || model.busy.contains(host), text: Self.label)
            .onChange(of: draft) { offerEdit() }
    }

    private static func label(_ size: Int) -> Text {
        size == 0 ? Text("None") : Text(verbatim: UIL10n.string("%@ GB", "\(size)")).monospacedDigit()
    }

    /// Tells the bar whether the swap waits
    private func offerEdit() {
        let field = $draft
        let edit = PendingRowEdits.Edit(
            id: "swap-\(host)", text: .apply,
            apply: { [model, host] in
                let asked = field.wrappedValue ?? 0
                await model.setSwap(sizeGB: asked == 0 ? nil : asked, host: host)
                field.wrappedValue = nil
                return true
            },
            revert: { field.wrappedValue = nil })
        edits.offer(edit, changed: draft != nil && draft != savedGB)
    }
}
