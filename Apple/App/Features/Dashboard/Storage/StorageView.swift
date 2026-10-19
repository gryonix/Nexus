import ServerControl
import ServiceCatalog
import SwiftUI

/// Which host's disks to show
struct StorageTarget: Hashable {
    let deployment: Deployment
    let host: SSHHostID
}

/// Arrays, their health, and repair when needed
struct StorageView: View {
    @StateObject private var model: StorageViewModel
    @State private var sheet: StorageSheet?

    init(target: StorageTarget) {
        _model = StateObject(wrappedValue: StorageViewModel(deployment: target.deployment, host: target.host))
    }

    var body: some View {
        Form {
            StorageArraysSection(model: model, sheet: $sheet)
            if let job = model.hardware?.diskJob, job.isRecent() {
                DiskJobSection(job: job)
            }
            if let hardware = model.hardware, RaidPlan.candidates(in: hardware).count >= 2 {
                Section {
                    Button("Build an array…") { sheet = .build }
                        .buttonStyle(.borderless)
                } footer: {
                    Text("Free disks can be joined into a new array. Everything on the disks you pick is erased.")
                }
            }
            if model.hardware?.disks.isEmpty == false {
                Section {
                    Button("Check disk health") { sheet = .health }
                        .buttonStyle(.borderless)
                } footer: {
                    Text("Temperature, hours, wear and bad sectors, as each disk reports them.")
                }
            }
            if let hardware = model.hardware {
                StorageDisksSection(disks: hardware.disks, sheet: $sheet)
            }
        }
        .navigationTitle("Disks and RAID")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_ARRAY_MANAGE"] != nil else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            if let array = model.arrays.first { sheet = .manage(array) }
        }
        #endif
        .task(id: model.isBusy) { await model.follow() }
        .refreshableWithShortcut { await model.load() }
        .sheet(item: $sheet) { shown in
            NavigationStack { content(of: shown) }
        }
    }

    @ViewBuilder private func content(of shown: StorageSheet) -> some View {
        switch shown {
        case .repair(let array): StorageRepairView(model: model, array: array)
        case .build: StorageBuildView(model: model)
        case .health: DiskHealthView(model: model)
        case .manage(let array): ArrayManageView(model: model, array: array)
        case .disk(let disk): DiskManageView(model: model, disk: disk)
        }
    }
}

/// The one sheet the disks screen shows at a time
enum StorageSheet: Identifiable {
    case repair(StorageArray)
    case build
    case health
    case manage(StorageArray)
    case disk(ServerDisk)

    var id: String {
        switch self {
        case .repair(let array): return "repair:" + array.id
        case .build: return "build"
        case .health: return "health"
        case .manage(let array): return "manage:" + array.id
        case .disk(let disk): return "disk:" + disk.id
        }
    }
}

/// Arrays with their health, repair and management
private struct StorageArraysSection: View {
    @ObservedObject var model: StorageViewModel
    @Binding var sheet: StorageSheet?

    var body: some View {
        Section {
            if model.arrays.isEmpty {
                Text(model.isLoading ? "Reading the disks…" : "No RAID arrays on this machine.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.arrays) { array in
                if ArrayChange.manages(array) {
                    Button { sheet = .manage(array) } label: { ArrayRow(array: array).wholeRowTappable() }
                        .buttonStyle(.plain)
                } else {
                    ArrayRow(array: array)
                }
                repair(array)
            }
        } header: {
            Text("RAID arrays")
        } footer: {
            if let error = model.errorMessage { Text(verbatim: error).foregroundStyle(.red) }
            else { Text("A degraded array still works, but one more failed disk can lose it. Replace the failed disk soon.") }
        }
    }

    @ViewBuilder private func repair(_ array: StorageArray) -> some View {
        if array.needsAttention && array.repairsHere {
            Button(array.state == .stopped ? "Bring back…" : "Replace a disk…") { sheet = .repair(array) }
                .buttonStyle(.borderless)
        } else if array.needsAttention {
            Text("Repair this array with its own tools on the server.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every disk, each opening its own management
private struct StorageDisksSection: View {
    let disks: [ServerDisk]
    @Binding var sheet: StorageSheet?

    var body: some View {
        Section {
            ForEach(disks) { disk in
                Button { sheet = .disk(disk) } label: {
                    LabeledContent(StorageText.title(disk)) {
                        Text(verbatim: StorageText.detail(disk)).font(.caption)
                    }
                    .wholeRowTappable()
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Disks")
        } footer: {
            Text("Tap a disk to see its serial number, format it or make its light blink.")
        }
    }
}

/// The background disk task, or how it ended
struct DiskJobSection: View {
    let job: DiskJob

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: StorageChangeText.outcome(job)).foregroundStyle(tint)
            } label: {
                Text(verbatim: StorageChangeText.job(job))
            }
            ForEach(Array(job.lastLines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Background disk job")
        } footer: {
            Text("It runs on the server, so the app can be closed. The screen refreshes by itself.")
        }
    }

    private var tint: Color {
        switch job.outcome {
        case .running: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }
}

/// Root sign-in plus the one repair this array needs
struct StorageRepairView: View {
    @ObservedObject var model: StorageViewModel
    let array: StorageArray
    @Environment(\.dismiss) private var dismiss
    @State private var replacement: String?
    @State private var confirmation = ""

    private var spares: [ServerDisk] {
        model.hardware.map { RaidRepairPlan.candidates(in: $0, for: array) } ?? []
    }

    private var step: StorageStep? {
        if array.state == .stopped {
            return .importing(array)
        }
        guard let disk = spares.first(where: { $0.path == replacement }),
              StoragePreparation.confirms(confirmation),
              array.kind != .zfs || !array.failed.isEmpty else { return nil }
        return .repair(array, with: disk)
    }

    var body: some View {
        Form {
            Section { ArrayRow(array: array) }
            if array.state != .stopped { spareSection }
            StorageSignInSection(model: model)
            StorageRunSection(model: model, title: array.state == .stopped ? "Bring back" : "Replace",
                              step: step) { dismiss() }
        }
        .navigationTitle(array.state == .stopped ? "Bring back the array" : "Replace a disk")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .task { await model.loadStoredSecret() }
    }

    @ViewBuilder private var spareSection: some View {
        Section {
            if spares.isEmpty {
                Text("No free disk to put in. Add a new disk to the server, then pull down to read the disks again.")
                    .foregroundStyle(.secondary)
            } else {
                WrappingPicker("New disk", selection: $replacement) {
                    Text("None").tag(String?.none)
                    ForEach(spares) { disk in
                        Text(verbatim: StorageText.choice(disk)).tag(String?.some(disk.path))
                    }
                }
                TextField(UIL10n.string("ERASE"), text: $confirmation).autocorrectionDisabled()
            }
        } header: {
            Text("Replacement")
        } footer: {
            Text("Everything on the new disk is erased. Type \(UIL10n.string("ERASE")) to confirm.")
        }
    }
}

/// Disks, RAID and the cache disk, on the General tab
struct StorageSection: View {
    let deployment: Deployment
    @ObservedObject var overview: StorageOverview

    private var hosts: [DeploymentNode] {
        deployment.nodes.filter { node in
            overview.hardware[node.sshHost].map(StorageOverview.manages) ?? false
        }
    }

    private var cacheHosts: [DeploymentNode] {
        deployment.nodes.filter { node in
            overview.hardware[node.sshHost].map { !FastStoragePlan.candidates(in: $0).isEmpty } ?? false
        }
    }

    var body: some View {
        if !hosts.isEmpty || !cacheHosts.isEmpty {
            Section("Storage") {
                ForEach(hosts, id: \.sshHost) { node in
                    NavigationLink(value: StorageTarget(deployment: deployment, host: node.sshHost)) {
                        Label(title(for: node), systemImage: "internaldrive")
                    }
                }
                ForEach(cacheHosts, id: \.sshHost) { node in
                    NavigationLink(value: CacheDiskTarget(deployment: deployment, host: node.sshHost)) {
                        Label(cacheTitle(for: node), systemImage: "bolt.horizontal")
                    }
                }
            }
        }
    }

    private func cacheTitle(for node: DeploymentNode) -> String {
        guard deployment.nodes.count > 1 else { return UIL10n.string("Cache disk") }
        let name = node.name.isEmpty ? node.endpoint.host : node.name
        return UIL10n.string("Cache disk — %@", name)
    }

    private func title(for node: DeploymentNode) -> String {
        guard deployment.nodes.count > 1 else { return UIL10n.string("Disks and RAID") }
        let name = node.name.isEmpty ? node.endpoint.host : node.name
        return UIL10n.string("Disks and RAID — %@", name)
    }
}

private extension View {
    /// The empty part of a row answers taps too
    func wholeRowTappable() -> some View {
        frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
