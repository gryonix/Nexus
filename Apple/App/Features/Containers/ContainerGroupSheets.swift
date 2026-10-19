import AgentControl
import ServerControl
import SwiftUI

// ─────────────────────────────── the log ───────────────────────────────

/// One group's log, followed live
@available(macOS 15.0, *)
struct ContainerGroupLogSheet: View {
    let deployment: Deployment
    let group: ContainerGroup
    @ObservedObject var model: ContainersFleetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [ContainerLogLine] = []
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if let failure {
                    ContentUnavailableView {
                        Label("The log could not be read", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text(verbatim: failure).textSelection(.enabled)
                    }
                } else if lines.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for output…").foregroundStyle(.secondary)
                    }
                } else {
                    logList
                }
            }
            .navigationTitle(Text(verbatim: group.displayName))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await follow() }
        .onDisappear { task?.cancel() }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: line.container)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(verbatim: line.text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .id(index)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .onChange(of: lines.count) { _, count in
                guard count > 0 else { return }
                withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    private func follow() async {
        task?.cancel()
        let key = group.key
        task = Task {
            do {
                let stream = try await model.logs(for: key, on: deployment)
                for try await line in stream {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        lines.append(line)
                        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { failure = DashboardViewModel.message(for: error) }
            }
        }
        await task?.value
    }
}

// ──────────────────────────── the backup plan ────────────────────────────

@available(macOS 15.0, *)
struct ContainerBackupPlanSheet: View {
    let deployment: Deployment
    let group: ContainerGroup
    @ObservedObject var model: ContainersFleetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var plan: ContainerBackupPlan?
    @State private var schedule: ContainerBackupSchedule?
    @State private var paths: [String] = []
    @State private var volumes: [String] = []
    @State private var failure: String?
    @State private var isSaving = false
    @State private var archives: ContainerBackupListing?
    @State private var archivesFailure: String?

    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    Section { Text(verbatim: failure).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if let plan {
                    planSections(plan)
                } else if failure == nil {
                    Section { HStack { ProgressView().controlSize(.small); Text("Working out what this would take…") } }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Backup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(plan == nil || isSaving)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func planSections(_ plan: ContainerBackupPlan) -> some View {
        Section {
            ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                Text(verbatim: path).font(.callout.monospaced())
                    .swipeActions { deleteButton { paths.remove(at: index) } }
            }
            if paths.isEmpty {
                Text("No directories.").foregroundStyle(.secondary)
            }
        } header: {
            InfoSectionHeader("Directories", note: "Removing a line here means it is not archived. What can be listed is limited to what this server reported for this group.")
        }

        if !volumes.isEmpty {
            Section("Volumes") {
                ForEach(Array(volumes.enumerated()), id: \.offset) { index, volume in
                    Text(verbatim: volume).font(.callout.monospaced())
                        .swipeActions { deleteButton { volumes.remove(at: index) } }
                }
            }
        }

        if !plan.databases.isEmpty {
            Section {
                ForEach(plan.databases) { database in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(database.database) · \(database.engine)")
                        Text(verbatim: database.container)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                InfoSectionHeader("Databases", note: "These are dumped with their own client rather than copied from disk. A copy taken while the database is running restores into a broken one, and it does that without any error at the time.")
            }
        }

        if plan.stopWhileArchiving {
            Section {
                Label("The group is stopped while the archive is taken.", systemImage: "pause.circle")
            } footer: {
                Text("A database was found that cannot be dumped separately, so a consistent archive needs the stack stopped.")
            }
        }

        if !plan.notes.isEmpty {
            Section("What the server worked out") {
                ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                    Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        scheduleSection
        archivesSection

        if !plan.isDetected {
            Section {
                Button("Use what the server detects") {
                    Task { await clearCorrection() }
                }
                .rowActionButtonStyle()
                .infoNote("Use what the server detects", "This plan was edited. Going back to detection lets the server work it out again from the images and mounts.")
            }
        }
    }

    @ViewBuilder
    private var archivesSection: some View {
        Section {
            if let archives {
                if archives.archives.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(archives.archives, id: \.path) { archive in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: archive.name)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(verbatim: archiveDetail(archive))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if archivesFailure == nil {
                HStack { ProgressView().controlSize(.small); Text("Reading the backup directory…") }
            } else if let archivesFailure {
                Text(verbatim: archivesFailure).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("Backups")
        } footer: {
            if let archives, !archives.directory.isEmpty {
                Text("Kept in \(archives.directory). Restoring one is not offered here yet — putting a stranger's volumes back over a running stack is a step this app does not take without proving it on a real server first.")
            } else {
                Text("Restoring one is not offered here yet — putting a stranger's volumes back over a running stack is a step this app does not take without proving it on a real server first.")
            }
        }
    }

    /// Size and date, or size alone
    private func archiveDetail(_ archive: ContainerArchive) -> String {
        let size = ByteCountFormatter.string(fromByteCount: archive.sizeBytes, countStyle: .file)
        guard let modified = archive.modifiedAt else { return size }
        return "\(size) · \(modified.formatted(date: .abbreviated, time: .shortened))"
    }

    private var scheduleSection: some View {
        Section {
            WrappingPicker("Automatic backup", selection: cadenceBinding) {
                Text("Off").tag(ContainerBackupCadence?.none)
                ForEach(ContainerBackupCadence.allCases) { cadence in
                    Text(cadence.title).tag(ContainerBackupCadence?.some(cadence))
                }
            }
            if let schedule, !schedule.lastOutcome.isEmpty {
                LabeledContent("Last run") {
                    Text(verbatim: schedule.lastOutcome)
                        .font(.caption)
                        .foregroundStyle(schedule.lastOutcome.hasPrefix("ok") ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                }
            }
        } header: {
            InfoSectionHeader("Automatic backup", note: "The server runs this on its own, so it does not need this device to be open.")
        }
    }

    private var cadenceBinding: Binding<ContainerBackupCadence?> {
        Binding(
            get: { schedule?.cadence },
            set: { value in Task { await setCadence(value) } })
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) { Label("Remove", systemImage: "trash") }
            .dangerTint()
    }

    private func load() async {
        do {
            let loaded = try await model.backupPlan(for: group.key, on: deployment)
            plan = loaded
            paths = loaded.paths
            volumes = loaded.volumes
            schedule = try? await model.backupSchedule(for: group.key, on: deployment)
            do {
                archives = try await model.backups(for: group.key, on: deployment)
            } catch {
                archivesFailure = DashboardViewModel.message(for: error)
            }
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }

    private func save() async {
        guard let plan else { return }
        isSaving = true
        defer { isSaving = false }
        let edited = ContainerBackupPlan(
            key: plan.key, paths: paths, volumes: volumes, databases: plan.databases,
            stopWhileArchiving: plan.stopWhileArchiving, isDetected: false, notes: plan.notes)
        do {
            _ = try await model.setBackupPlan(edited, for: group.key, on: deployment)
            dismiss()
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }

    private func clearCorrection() async {
        do {
            let fresh = try await model.setBackupPlan(nil, for: group.key, on: deployment)
            plan = fresh
            paths = fresh.paths
            volumes = fresh.volumes
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }

    private func setCadence(_ cadence: ContainerBackupCadence?) async {
        do {
            schedule = try await model.setBackupSchedule(cadence, for: group.key, on: deployment)
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }
}

extension ContainerBackupCadence {
    var title: LocalizedStringKey {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }
}

// ───────────────────────────── removing one ─────────────────────────────

@available(macOS 15.0, *)
struct ContainerRemovalSheet: View {
    let deployment: Deployment
    let group: ContainerGroup
    @ObservedObject var model: ContainersFleetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var purgeData = false
    @State private var purgeBackups = false
    @State private var preview: ContainerRemovalPreview?
    @State private var failure: String?
    @State private var isRunning = false
    @State private var log: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Also delete its data", isOn: $purgeData)
                    Toggle("Also delete its backups", isOn: $purgeBackups)
                } footer: {
                    Text("With both off, the containers are stopped and removed and everything they held stays on the server.")
                }

                if let preview {
                    previewSections(preview)
                }

                if !log.isEmpty {
                    Section("What the server did") {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.caption.monospaced())
                        }
                    }
                }

                if let failure {
                    Section { Text(verbatim: failure).foregroundStyle(.red).textSelection(.enabled) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(verbatim: group.displayName))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove", role: .destructive) { Task { await remove() } }
                        .disabled(isRunning)
                        .dangerTint()
                }
            }
        }
        .task { await loadPreview() }
        .onChange(of: purgeData) { _, _ in Task { await loadPreview() } }
        .onChange(of: purgeBackups) { _, _ in Task { await loadPreview() } }
    }

    @ViewBuilder
    private func previewSections(_ preview: ContainerRemovalPreview) -> some View {
        Section("Containers") {
            ForEach(preview.containers, id: \.self) { name in
                Text(verbatim: name).font(.callout.monospaced())
            }
        }
        if !preview.volumes.isEmpty {
            Section("Volumes") {
                ForEach(preview.volumes, id: \.self) { name in
                    Text(verbatim: name).font(.callout.monospaced())
                }
            }
        }
        if !preview.paths.isEmpty {
            Section("Directories") {
                ForEach(preview.paths, id: \.self) { path in
                    Text(verbatim: path).font(.callout.monospaced())
                }
            }
        }
        if !preview.backupPaths.isEmpty {
            Section("Backups") {
                ForEach(preview.backupPaths, id: \.self) { path in
                    Text(verbatim: path).font(.callout.monospaced())
                }
            }
        }
        if !preview.notes.isEmpty {
            Section {
                ForEach(Array(preview.notes.enumerated()), id: \.offset) { _, note in
                    Text(verbatim: note).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                InfoSectionHeader("Left alone", note: "These are named because the server refused to delete them, not because it forgot them.")
            }
        }
    }

    private func loadPreview() async {
        do {
            preview = try await model.removalPreview(for: group.key, on: deployment,
                                                     purgeData: purgeData, purgeBackups: purgeBackups)
        } catch {
            failure = DashboardViewModel.message(for: error)
        }
    }

    private func remove() async {
        isRunning = true
        let island = IslandRun(title: UIL10n.string("Removing %@", group.displayName),
                               serverName: deployment.name,
                               progressText: UIL10n.string("Stopping and removing containers…"),
                               deployment: deployment)
        defer { isRunning = false }
        do {
            try await model.remove(group.key, on: deployment, purgeData: purgeData,
                                   purgeBackups: purgeBackups) { line in
                Task { @MainActor in
                    log.append(line)
                    island.update(line)
                }
            }
            island.finish(UIL10n.string("%@ was deleted.", group.displayName))
            dismiss()
        } catch {
            failure = DashboardViewModel.message(for: error)
            island.finish("", error: failure)
        }
    }
}

// ──────────────────── running a backup, and updating ────────────────────

@available(macOS 15.0, *)
enum ContainerUpdateOffer {
    static func mayUpdateWithoutBackup(kind: ContainerOperationSheet.Kind,
                                       alreadySkipped: Bool,
                                       error: Error) -> Bool {
        kind == .update
            && !alreadySkipped
            && AgentContainerOperations.namesNothingToArchive(error)
    }
}

@available(macOS 15.0, *)
struct ContainerOperationSheet: View {
    enum Kind: Hashable { case backup, update }

    let deployment: Deployment
    let group: ContainerGroup
    let kind: Kind
    @ObservedObject var model: ContainersFleetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var log: [String] = []
    @State private var outcome: String?
    @State private var failure: String?
    @State private var isRunning = true
    @State private var mayUpdateWithoutBackup = false
    @State private var skippedBackup = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(runningTitle)
                        }
                    } else if let outcome {
                        Text(verbatim: outcome)
                    }
                }
                if !log.isEmpty {
                    Section("What the server did") {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                if let failure {
                    Section { Text(verbatim: failure).foregroundStyle(.red).textSelection(.enabled) }
                }
                if mayUpdateWithoutBackup && !isRunning {
                    Section {
                        Button {
                            Task { await run(skippingBackup: true) }
                        } label: {
                            Label("Update without a backup", systemImage: "arrow.down.circle")
                        }
                        .rowActionButtonStyle()
                        .infoNote("Update without a backup", "This group keeps nothing outside its images — no volume, no folder from the server and no database — so there is nothing a backup could have saved. Updating it pulls the newer images and starts them again; if that fails, the previous images are put back.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(verbatim: group.displayName))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(isRunning)
                }
            }
        }
        .interactiveDismissDisabled(isRunning)
        .task { await run() }
    }

    private var islandTitle: String {
        kind == .backup
            ? UIL10n.string("Backing up %@", group.displayName)
            : UIL10n.string("Updating %@", group.displayName)
    }

    private var runningTitle: LocalizedStringKey {
        if kind == .backup { return "Backing up…" }
        return skippedBackup ? "Updating without a backup…" : "Updating…"
    }

    private func run(skippingBackup: Bool = false) async {
        isRunning = true
        mayUpdateWithoutBackup = false
        skippedBackup = skippingBackup
        failure = nil
        outcome = nil
        log = []
        let island = IslandRun(title: islandTitle, serverName: deployment.name,
                               progressText: UIL10n.string("Starting…"), deployment: deployment)
        defer {
            isRunning = false
            island.finish(outcome ?? "", error: failure)
        }
        let note: @Sendable (String) -> Void = { line in
            Task { @MainActor in
                log.append(line)
                island.update(line)
            }
        }
        do {
            switch kind {
            case .backup:
                let archive = try await model.runBackup(for: group.key, on: deployment, onLine: note)
                outcome = archive.map {
                    UIL10n.string("Backed up to %@", $0.path)
                } ?? UIL10n.string("The backup finished.")
            case .update:
                let result = try await model.update(group.key, on: deployment,
                                                    skipBackup: skippingBackup, onLine: note)
                switch result {
                case .updated:
                    outcome = UIL10n.string("Updated and running.")
                case .alreadyCurrent:
                    outcome = UIL10n.string("Every image is already the newest published.")
                case .rolledBack(let why):
                    outcome = UIL10n.string("The update failed and was rolled back: %@", why)
                }
            }
        } catch {
            failure = DashboardViewModel.message(for: error)
            mayUpdateWithoutBackup = ContainerUpdateOffer.mayUpdateWithoutBackup(
                kind: kind, alreadySkipped: skippingBackup, error: error)
        }
    }
}
