import AgentClient
import ServerControl
import ServiceCatalog
import SwiftUI

@available(macOS 15.0, *)
struct ModelsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var listing = LocalModels.Listing()
    @State private var loading = true
    @State private var wanted = ""
    @State private var pulling: LocalModels.Progress?
    @State private var failure: String?
    @State private var removing: String?
    /// True from the tap until the run reports it stopped
    @State private var stopping = false

    var body: some View {
        CardList {
            if loading {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Reading the server's models…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !listing.enginePresent {
                Section {
                    Label("No model engine is installed on this server.",
                          systemImage: "cpu")
                        .font(.callout)
                } footer: {
                    Text("Add Ollama to this server from the catalog, then come back.")
                }
            } else {
                installedSection
                fetchSection
            }
        }
        .navigationTitle(Text("Models"))
        .task { await load() }
        #if DEBUG
        .task {
            guard let text = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_MODEL_PULL"]
            else { return }
            var step = LocalModels.Progress()
            step.text = text
            step.jobID = "demo-pull"
            step.completed = 3_221_225_472
            step.total = 8_589_934_592
            pulling = step
        }
        #endif
    }

    @ViewBuilder
    private var installedSection: some View {
        Section {
            if listing.models.isEmpty {
                Text("No models yet. Fetch one below — the engine is installed and empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(listing.models, id: \.name) { model in
                    modelRow(model)
                }
            }
        } header: {
            Text("On this server")
        } footer: {
            if !listing.path.isEmpty {
                Text(verbatim: listing.path)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: Gryonixnexusd_V1_Model) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.name)
                    .textSelection(.enabled)
                Text(verbatim: [ByteSize.human(model.sizeBytes),
                                model.parameterSize,
                                model.quantization]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if removing == model.name {
                ProgressView()
            } else {
                Button(role: .destructive) {
                    Task { await remove(model.name) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .dangerTint()
                .disabled(pulling != nil)
            }
        }
    }

    @ViewBuilder
    private var fetchSection: some View {
        Section {
            if let pulling {
                progressRow(pulling)
            } else {
                TechnicalField(title: "Model name", prompt: "llama3.2:3b", text: $wanted)
                Button {
                    Task { await fetch() }
                } label: {
                    Text("Fetch")
                }
                .disabled(wanted.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            InfoSectionHeader("Fetch a model", note: "The name is the one the model registry uses, tag included. The download runs on the server — you can close this screen.")
        } footer: {
            Text("\(ByteSize.human(listing.freeBytes)) free of \(ByteSize.human(listing.totalBytes))")
        }
    }

    @ViewBuilder
    private func progressRow(_ step: LocalModels.Progress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = step.fraction {
                ProgressView(value: fraction)
                Text(verbatim: "\(ByteSize.human(step.completed)) / \(ByteSize.human(step.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            if !step.text.isEmpty {
                Text(verbatim: step.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !step.jobID.isEmpty, !step.finished {
                if stopping {
                    Text("Stopping…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(role: .destructive) {
                        Task { await stop(jobID: step.jobID) }
                    } label: {
                        Text("Stop the download")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .dangerTint()
                }
            }
        }
    }

    /// Ask the host to stop the fetch
    private func stop(jobID: String) async {
        stopping = true
        defer { stopping = false }
        if let refusal = await LocalModels.stop(jobID: jobID, deployment: viewModel.deployment) {
            failure = refusal
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let fetched = await LocalModels.list(deployment: viewModel.deployment)
        if let problem = fetched.failure {
            failure = problem
            return
        }
        listing = fetched
        failure = nil
    }

    private func fetch() async {
        let name = wanted.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        failure = nil
        pulling = LocalModels.Progress()
        let island = IslandRun(title: UIL10n.string("Fetching %@", name),
                               serverName: viewModel.deployment.name,
                               progressText: UIL10n.string("Starting…"), deployment: viewModel.deployment)
        defer {
            pulling = nil
            island.finish(failure == nil ? UIL10n.string("%@ is ready.", name) : "", error: failure)
        }
        for await step in LocalModels.pull(name, deployment: viewModel.deployment) {
            pulling = step
            island.update(Self.islandLine(step), progress: step.fraction)
            if step.finished {
                if let listed = step.listing { listing = listed }
                if !step.text.isEmpty, step.listing == nil || !listing.models.contains(where: { $0.name == name }) {
                    failure = step.text
                }
            }
        }
        wanted = ""
    }

    private static func islandLine(_ step: LocalModels.Progress) -> String {
        guard step.total > 0 else { return step.text }
        return "\(ByteSize.human(step.completed)) / \(ByteSize.human(step.total))"
    }

    private func remove(_ name: String) async {
        removing = name
        defer { removing = nil }
        let fresh = await LocalModels.delete(name, deployment: viewModel.deployment)
        if let problem = fresh.failure {
            failure = problem
            return
        }
        listing = fresh
        failure = nil
    }
}

/// Bytes as a person reads them
enum ByteSize {
    static func human(_ bytes: UInt64) -> String {
        let gb: Double = 1_073_741_824
        let mb: Double = 1_048_576
        let value = Double(bytes)
        if value >= gb { return String(format: "%.1f GB", value / gb) }
        if value >= mb { return String(format: "%.0f MB", value / mb) }
        return "\(bytes) B"
    }
}
