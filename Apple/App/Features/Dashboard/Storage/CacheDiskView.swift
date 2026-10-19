import ServerControl
import ServiceCatalog
import SwiftUI

struct CacheDiskTarget: Hashable {
    let deployment: Deployment
    let host: SSHHostID
}

/// Moves databases and caches to a fast disk and back
struct CacheDiskView: View {
    @StateObject private var model: StorageViewModel
    @State private var disk: String?
    @State private var mirror: String?
    @State private var projects: [FastStorageMove.Project]?
    @State private var bound: Set<String> = []
    @State private var asking: CacheQuestion?

    init(target: CacheDiskTarget) {
        _model = StateObject(wrappedValue: StorageViewModel(deployment: target.deployment, host: target.host))
    }

    private var candidates: [ServerDisk] { model.hardware.map(FastStoragePlan.candidates(in:)) ?? [] }
    private var chosen: ServerDisk? { candidates.first { $0.path == disk } }
    private var partners: [ServerDisk] {
        guard let chosen, chosen.isBlank else { return [] }
        return candidates.filter { $0.isBlank && $0.path != chosen.path }
    }
    private var waiting: [FastStorageMove.Project] {
        (projects ?? []).compactMap { project in
            let left = project.hotPaths.filter { !bound.contains($0) }
            return left.isEmpty ? nil : .init(directory: project.directory, hotPaths: left)
        }
    }
    private var moved: [FastStorageMove.Project] {
        (projects ?? []).filter { project in project.hotPaths.contains { bound.contains($0) } }
    }

    var body: some View {
        Form {
            CacheDiskChoice(candidates: candidates, partners: partners, disk: $disk, mirror: $mirror,
                            loading: model.isLoading)
            StorageSignInSection(model: model)
            findSection
            if let projects { CacheDiskMoves(projects: projects, bound: bound) }
            actions
        }
        .navigationTitle("Cache disk")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await model.load()
            await model.loadStoredSecret()
            if disk == nil { disk = candidates.first?.path }
        }
        .confirmationDialog(asking?.title ?? "", isPresented: Binding(get: { asking != nil },
                                                                      set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { question in
            Button(question.confirm, role: question.destructive ? .destructive : nil) {
                Task { await perform(question) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { question in
            Text(question.message)
        }
    }

    private var findSection: some View {
        Section {
            Button(projects == nil ? "Find what moves" : "Read again") { Task { await find() } }
                .disabled(model.runningStep != nil)
        } footer: {
            if let running = model.runningStep {
                Label(running, systemImage: "hourglass")
            } else if let failure = model.stepFailure {
                Text(verbatim: failure).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if !waiting.isEmpty, chosen != nil {
            Section {
                Button("Move to the cache disk") { asking = .move }
            }
        }
        if !moved.isEmpty {
            Section {
                Button("Return to the system disk") { asking = .restore }
                Button("Delete old copies", role: .destructive) { asking = .cleanup }
                    .dangerTint()
            } footer: {
                Text("Old copies (.before-cache) are what the folders held before the move. Delete them once everything works.")
            }
        }
    }

    private func find() async {
        let step = StorageStep.cacheProbe(title: UIL10n.string("Reading the services…"),
                                          script: "#!/bin/bash\n\(FastStorageMove.probeCommand)\necho \(Self.probeDone)\n",
                                          doneMarker: Self.probeDone)
        guard let output = await model.output(of: step) else { return }
        projects = FastStorageMove.projects(inProbe: output)
        bound = FastStorageMove.bound(inProbe: output)
    }

    private func perform(_ question: CacheQuestion) async {
        switch question {
        case .move: await move()
        case .restore:
            await model.run(.cacheRestore(moved))
        case .cleanup:
            await model.run(.cacheCleanup(bound.sorted()))
        }
        await find()
    }

    private func move() async {
        guard let chosen else { return }
        var target = FastStoragePlan(disk: chosen, hotPaths: []).target
        if let partner = partners.first(where: { $0.path == mirror }) {
            let pair = RaidPlan.cacheMirror([chosen, partner])
            await model.run(.raid(pair, title: UIL10n.string("Mirroring the cache disks…")))
            guard model.stepFailure == nil else { return }
            target = .device(pair.device)
        }
        await model.run(.cacheMove(FastStorageMove(target: target, projects: waiting)))
    }

    private static let probeDone = "GRYONIXNEXUS_FAST_PROBE_DONE"
}

/// What the confirmation asks
private enum CacheQuestion: Identifiable {
    case move, restore, cleanup

    var id: Self { self }

    var title: String {
        switch self {
        case .move: return UIL10n.string("Move databases to the cache disk?")
        case .restore: return UIL10n.string("Return the folders to the system disk?")
        case .cleanup: return UIL10n.string("Delete the old copies?")
        }
    }

    var message: String {
        switch self {
        case .move, .restore:
            return UIL10n.string("Each service stops while its data is copied, then starts again. The old copy stays beside it as .before-cache.")
        case .cleanup:
            return UIL10n.string("They cannot be brought back. The data the services use now is not touched.")
        }
    }

    var confirm: String {
        switch self {
        case .move: return UIL10n.string("Move")
        case .restore: return UIL10n.string("Return")
        case .cleanup: return UIL10n.string("Delete")
        }
    }

    var destructive: Bool { self == .cleanup }
}

/// Which fast disk takes the databases, and its mirror
private struct CacheDiskChoice: View {
    let candidates: [ServerDisk]
    let partners: [ServerDisk]
    @Binding var disk: String?
    @Binding var mirror: String?
    let loading: Bool

    var body: some View {
        Section {
            if candidates.isEmpty {
                Text(loading ? "Reading the disks…" : "No free SSD or NVMe besides the system disk.")
                    .foregroundStyle(.secondary)
            } else {
                WrappingPicker("Cache disk", selection: $disk) {
                    ForEach(candidates) { disk in
                        Text(verbatim: StorageText.choice(disk)).tag(String?.some(disk.path))
                    }
                }
            }
            if !partners.isEmpty {
                WrappingPicker("Mirror onto", selection: $mirror) {
                    Text("None").tag(String?.none)
                    ForEach(partners) { disk in
                        Text(verbatim: StorageText.choice(disk)).tag(String?.some(disk.path))
                    }
                }
            }
        } footer: {
            Text("Databases and caches move to this disk; photos, files and media stay where they are. An empty disk is formatted, a disk with files keeps them.")
        }
    }
}

/// What moves, service by service
private struct CacheDiskMoves: View {
    let projects: [FastStorageMove.Project]
    let bound: Set<String>

    var body: some View {
        Section("Moves") {
            if projects.isEmpty {
                Text("Nothing to move: no service here keeps a database or cache in its own folder.")
                    .foregroundStyle(.secondary)
            }
            ForEach(projects, id: \.directory) { project in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: (project.directory as NSString).lastPathComponent)
                    ForEach(project.hotPaths, id: \.self) { path in
                        Label {
                            Text(verbatim: path).font(.caption.monospaced())
                        } icon: {
                            Image(systemName: bound.contains(path) ? "bolt.fill" : "internaldrive")
                        }
                        .foregroundStyle(bound.contains(path) ? .green : .secondary)
                    }
                }
            }
        }
    }
}
