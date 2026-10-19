import AgentClient
import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI
import UniformTypeIdentifiers

@available(macOS 15.0, *)
struct ModsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onUpdate: (Deployment) -> Void

    @State private var query = ""
    @State private var searching = false
    @State private var results = ServerMods.SearchOutcome()
    @State private var picked: [String] = []
    @State private var applied: [String] = []
    @State private var adding: String?
    @State private var files = ServerMods.Files()
    @State private var loadingFiles = true
    @State private var importing = false
    @State private var uploading = false
    @State private var failure: String?

    private var settings: ServiceSettings { viewModel.deployment.serviceSettings }
    private var flavour: String { settings.minecraftJavaFlavour }
    private var loader: String? { AgentModOperations.loader(forFlavour: flavour) }
    private var gameVersion: String { settings.minecraftJavaVersion.trimmingCharacters(in: .whitespaces) }
    /// Paper loads plugins, Fabric and Forge load mods
    private var callsThemPlugins: Bool { AgentModOperations.slot(forFlavour: flavour) == .plugins }

    var body: some View {
        CardList {
            serverSection
            if loader != nil {
                pickedSection
                searchSection
            }
            filesSection
        }
        .navigationTitle(callsThemPlugins ? Text("Plugins") : Text("Mods"))
        .task {
            picked = AgentModOperations.entries(in: settings.minecraftJavaMods)
            applied = picked
            await reloadFiles()
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await upload(url) }
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
    }

    // MARK: - The server itself

    @ViewBuilder
    private var serverSection: some View {
        Section {
            LabeledContent("Server type", value: flavour.capitalized)
            LabeledContent("Game version",
                           value: gameVersion.isEmpty ? UIL10n.string("latest") : gameVersion)
        } header: {
            Text("This server")
        } footer: {
            if loader == nil {
                Text("A Vanilla server loads no mods at all. Change the server type to Fabric or Forge (mods) or Paper (plugins) in the configurator, then come back.")
            } else if gameVersion.isEmpty {
                Text("This server follows the latest game release, so the list below is not filtered by version and a mod may stop fitting after an update. Pin a game version in the configurator to filter it.")
            } else if callsThemPlugins {
                Text("Plugins run on the server only — players join with an unmodified game.")
            } else {
                Text("Players need the same mods in their own game to join.")
            }
        }
    }

    // MARK: - What is picked

    @ViewBuilder
    private var pickedSection: some View {
        Section {
            if picked.isEmpty {
                Text("Nothing picked yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(picked, id: \.self) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AgentModOperations.slug(ofEntry: entry))
                                .font(.callout)
                            Text(entry.contains(":") ? UIL10n.string("pinned to one build")
                                                     : UIL10n.string("not pinned"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            picked.removeAll { $0 == entry }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .dangerTint()
                    }
                }
            }
            if picked != applied {
                Button {
                    Task { await apply() }
                } label: {
                    Label("Apply to the server", systemImage: "arrow.down.circle")
                }
            }
        } header: {
            Text("Picked")
        } footer: {
            if picked != applied {
                Text("The server is installed again with this list, which takes a few minutes and restarts the world. Removing an entry deletes its file from the server.")
            } else {
                Text("Every entry is pinned to one build, so a restart cannot move this world onto a version nobody chose.")
            }
        }
    }

    // MARK: - The catalogue

    @ViewBuilder
    private var searchSection: some View {
        Section {
            HStack {
                TextField("Search", text: $query, prompt: Text("map, backpack, sodium…"))
                    .onSubmit { Task { await runSearch() } }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                Button {
                    Task { await runSearch() }
                } label: {
                    if searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                }
                .buttonStyle(.borderless)
                .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let failure = results.failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(results.projects, id: \.projectID) { project in
                projectRow(project)
            }
        } header: {
            Text("Search the catalogue")
        } footer: {
            if results.projects.isEmpty {
                Text("The server runs the search and downloads what you pick — this device never talks to the mod site.")
            } else if !results.filteredByVersion {
                Text("Not filtered by game version — check that a mod supports this server before adding it.")
            } else {
                Text("Filtered to what this server can load.")
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Gryonixnexusd_V1_ModProject) -> some View {
        let slug = project.slug.isEmpty ? project.projectID : project.slug
        let already = picked.contains { AgentModOperations.slug(ofEntry: $0) == slug }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.title).font(.callout.weight(.medium))
                Spacer()
                if already {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else if adding == slug {
                    ProgressView()
                } else {
                    Button {
                        Task { await add(project) }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            // `description_p`: SwiftProtobuf renames the field, because `description` is already `CustomStringConvertible`'s.
            Text(project.description_p)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Label(downloads(project.downloads), systemImage: "arrow.down.circle")
                if !project.license.isEmpty {
                    Text(project.license)
                }
                if !project.author.isEmpty {
                    Text(project.author)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        Section {
            if loadingFiles {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading the server's files…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let failure = files.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            } else if files.files.isEmpty {
                Text("Nothing uploaded.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(files.files, id: \.name) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).font(.callout)
                            Text(size(file.sizeBytes)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await remove(file) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .dangerTint()
                    }
                }
            }
            Button {
                importing = true
            } label: {
                if uploading {
                    HStack(spacing: 8) { ProgressView(); Text("Uploading…") }
                } else {
                    Label("Upload a .jar…", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(uploading || !viewModel.deployment.usesAgent)
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Uploaded files")
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                if callsThemPlugins {
                    Text("Files you send up go straight into the server's plugins directory and survive updates and changes to the list above. Restart the server from its card to load a new one.")
                } else {
                    Text("Files you send up go straight into the server's mods directory and survive updates and changes to the list above. Restart the server from its card to load a new one.")
                }
                if files.freeBytes > 0 {
                    Text("\(size(files.freeBytes)) free on the server.")
                }
            }
        }
    }

    // MARK: - Actions

    private func runSearch() async {
        guard let loader else { return }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        results = await ServerMods.search(query: text,
                                          gameVersion: gameVersion,
                                          loader: loader,
                                          deployment: viewModel.deployment)
        searching = false
    }

    private func add(_ project: Gryonixnexusd_V1_ModProject) async {
        guard let loader else { return }
        let slug = project.slug.isEmpty ? project.projectID : project.slug
        adding = slug
        defer { adding = nil }
        switch await ServerMods.pinnedEntry(for: project,
                                            gameVersion: gameVersion,
                                            loader: loader,
                                            deployment: viewModel.deployment) {
        case .entry(let entry):
            if !picked.contains(entry) { picked.append(entry) }
        case .refused(let message):
            failure = message
        }
    }

    private func apply() async {
        let setting = AgentModOperations.setting(from: picked)
        guard let updated = await viewModel.applyMinecraftMods(setting) else { return }
        onUpdate(updated)
        applied = picked
    }

    private func reloadFiles() async {
        loadingFiles = true
        files = await ServerMods.files(deployment: viewModel.deployment)
        loadingFiles = false
    }

    private func upload(_ url: URL) async {
        uploading = true
        defer { uploading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let outcome = await ServerMods.upload(name: url.lastPathComponent,
                                                  slot: AgentModOperations.slot(forFlavour: flavour),
                                                  content: data,
                                                  deployment: viewModel.deployment)
            if let message = outcome.failure {
                failure = message
            } else {
                files = outcome
                failure = nil
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func remove(_ file: Gryonixnexusd_V1_ModFile) async {
        let outcome = await ServerMods.delete(name: file.name,
                                              slot: file.slot,
                                              deployment: viewModel.deployment)
        if let message = outcome.failure { failure = message } else { files = outcome }
    }

    // MARK: - Formatting

    private func downloads(_ count: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
