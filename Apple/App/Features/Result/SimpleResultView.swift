import SwiftUI
import gryonixNexusCore
import MailRecipe
import ServerControl
import ServiceCatalog

struct SimpleResultView: View {
    let bundle: GeneratedBundle
    var deployment: Deployment?
    var openPorts: [OpenPortRequirement] = []
    var resumingRunningInstall = false
    var resumingViewModel: InstallViewModel?

    @State private var dismiss = DismissHandle()
    @State private var index = 0
    @State private var shareURLs: [URL] = []
    @State private var shareDirectory: URL?
    @State private var sortPortsByProtocol = false
    @State private var asking: LicenseGate.Reason?
    @ObservedObject private var license = LicenseStore.shared
    #if DEBUG
    /// Auto-drive only (`InstallResetProbe`): pushes InstallFlowView
    @State private var debugPushInstall = false
    #endif

    private var entryIsVPS: Bool {
        bundle.artifacts.contains { $0.server == .vpsRelay }
    }

    private enum Page: Hashable { case install, warnings, dns, ports, notes }

    private var dnsArtifacts: [Artifact] {
        bundle.artifacts.filter { $0.kind == .dnsRecord }
    }

    private var pages: [Page] {
        var p: [Page] = [.install]
        if !bundle.warnings.isEmpty { p.append(.warnings) }
        if !dnsArtifacts.isEmpty { p.append(.dns) }
        if !openPorts.isEmpty { p.append(.ports) }
        if !bundle.notes.isEmpty { p.append(.notes) }
        return p
    }

    private var current: Page { pages[min(index, pages.count - 1)] }

    private var groups: [(title: LocalizedStringKey, artifacts: [Artifact])] {
        let order: [(ServerRole?, LocalizedStringKey)] = [
            (.singleHost, "Server"),
            (.vpsRelay, "VPS (entry point)"),
            (.homeBackend, "Local server")
        ]
        return order.compactMap { role, title in
            let items = bundle.artifacts.filter { $0.server == role }
            return items.isEmpty ? nil : (title, items)
        }
    }

    var body: some View {
        screen.dismissHandle(dismiss)
    }

    @ViewBuilder private var screen: some View {
        CardList {
            switch current {
            case .install: installPage
            case .warnings: warningsPage
            case .dns: dnsPage
            case .ports: portsPage
            case .notes: notesPage
            }
        }
        .navigationTitle("Installation")
        .raisedNavigationTitle()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .wizardBack) {
                Button {
                    if index > 0 { withAnimation { index -= 1 } } else { dismiss() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
            if !license.status.isActive {
                ToolbarItem(placement: .primaryAction) {
                    Button { asking = LicenseGate.reason } label: {
                        Label("Share bundle", systemImage: "lock.fill")
                    }
                }
            } else if !shareURLs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(items: shareURLs) {
                        Label("Share bundle", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .ownsBottomEdge()
        .licenseAsk($asking)
        .task { if license.status.isActive { prepareShareFiles() } }
        .onDisappear { cleanupShareFiles() }
        #if DEBUG
        .modifier(InstallResetAutoPush(isPresented: $debugPushInstall,
                                       deployment: deployment, bundle: bundle))
        #endif
    }

    // MARK: - Pages

    @ViewBuilder
    private var installPage: some View {
        if let deployment {
            MinimumRequirementsSection(deployment: deployment)
        }

        Section {
            if let resumingViewModel {
                NavigationLink {
                    InstallFlowView(session: resumingViewModel)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Installation is running on the server")
                                .font(.headline)
                            Text("Tap to see its live progress and log.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.tint)
                    }
                }
            } else if resumingRunningInstall {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Installation is running on the server")
                            .font(.headline)
                        Text("Its progress is in the bar at the bottom of the screen. The records and ports below are what you still need to add.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.tint)
                }
            } else if let deployment {
                NavigationLink {
                    InstallFlowView(deployment: deployment, bundle: bundle)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Install from this device")
                                .font(.headline)
                            Text("The app connects over SSH, runs the scripts and shows live progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.tint)
                    }
                }
            } else {
                Label("To install from this device, enable «Agent access» in the form — the app needs its SSH key on the server.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Install")
        }

        ForEach(Array(groups.enumerated()), id: \.offset) { offset, group in
            Section {
                ForEach(group.artifacts) { artifact in
                    NavigationLink {
                        ArtifactDetailView(artifact: artifact)
                    } label: {
                        SimpleArtifactRow(artifact: artifact)
                    }
                }
            } header: {
                Text(group.title)
            } footer: {
                if offset == groups.count - 1 {
                    Text("Or run the script yourself on the server — open it to copy or share the file.")
                }
            }
        }
    }

    @ViewBuilder
    private var warningsPage: some View {
        Section("Important") {
            ForEach(bundle.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var portsPage: some View {
        Section {
            Picker("Sort by", selection: $sortPortsByProtocol) {
                Text("Port").tag(false)
                Text("Protocol").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            ForEach(sortPortsByProtocol ? openPorts.sortedByProtocol() : openPorts.sortedByPort()) { requirement in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(requirement.port)/\(requirement.proto.rawValue)")
                        .font(.callout.monospaced())
                        .fixedSize()
                    Spacer(minLength: 12)
                    Text(verbatim: requirement.purpose)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            InfoSectionHeader(entryIsVPS ? "Ports to open on the VPS" : "Ports to open on the server",
                              note: "The script configures the server's own firewall itself. This list is for the hoster's external firewall (security groups) and reflects only the selected services — disable a service and its ports disappear.")
        }
    }

    @ViewBuilder
    private var dnsPage: some View {
        Section {
            ForEach(dnsArtifacts) { artifact in
                NavigationLink {
                    ArtifactDetailView(artifact: artifact)
                } label: {
                    SimpleArtifactRow(artifact: artifact)
                }
            }
        } header: {
            InfoSectionHeader("DNS records", note: "The same records come in three formats: a manual list, a standard BIND zone file, and a generic CSV. Most DNS providers — Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun and others — can import the zone file or the CSV directly, so you don't have to enter every record by hand.")
        }
    }

    @ViewBuilder
    private var notesPage: some View {
        Section("How to apply") {
            ForEach(bundle.notes, id: \.self) { note in
                Text(note)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if index < pages.count - 1 {
            nextBar
        } else if let deployment, license.status.isActive {
            Button {
                AppNavigator.shared.openServer(deployment.id)
            } label: {
                Text("Open server")
                    .font(.headline)
                    .frame(maxWidth: 420)
                    .padding(.vertical, 6)
            }
            .prominentActionButtonStyle()
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var nextBar: some View {
        Button {
            withAnimation { index += 1 }
        } label: {
            Text("Next")
                .font(.headline)
                .frame(maxWidth: 420)
                .padding(.vertical, 6)
        }
        .prominentActionButtonStyle()
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Bundle sharing

    private func prepareShareFiles() {
        cleanupShareFiles()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle-share-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            var urls: [URL] = []
            var seen = Set<String>()
            for artifact in bundle.artifacts {
                var name = artifact.fileName
                if !seen.insert(name).inserted {
                    name = "\(urls.count)-\(name)"
                }
                let url = directory.appendingPathComponent(name)
                try Data(artifact.contents.utf8).write(to: url, options: .atomic)
                urls.append(url)
            }
            shareDirectory = directory
            shareURLs = urls
        } catch {
            try? FileManager.default.removeItem(at: directory)
            shareDirectory = nil
            shareURLs = []
        }
    }

    private func cleanupShareFiles() {
        if let shareDirectory {
            try? FileManager.default.removeItem(at: shareDirectory)
        }
        shareDirectory = nil
        shareURLs = []
    }
}

struct SimpleArtifactRow: View {
    let artifact: Artifact

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: artifact.kind.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(artifact.fileName)
                    .font(.headline.monospaced())
                Text(artifact.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The icon a generated artifact is listed with
extension ArtifactKind {
    var systemImage: String {
        switch self {
        case .serverConfig: return "doc.text"
        case .dnsRecord: return "globe"
        case .shellScript: return "terminal"
        case .keyMaterial: return "key"
        case .firewallRules: return "shield"
        }
    }
}

private struct MinimumRequirementsSection: View {
    let deployment: Deployment

    var body: some View {
        let req = ServiceRegistry.requirements(for: deployment.services)
        return Section {
            LabeledContent("Operating system") {
                Text(verbatim: "Debian 12+ / Ubuntu 22.04+ · 64-bit (ARM64/x86-64)")
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Memory") {
                Text("At least \(String(req.memoryGB)) GB")
            }
            LabeledContent("Disk") {
                Text("At least \(String(req.diskGB)) GB")
            }
            LabeledContent("Access") {
                Text("Root to run the setup, revoked at the end")
                    .multilineTextAlignment(.trailing)
            }
            if req.installsDocker {
                LabeledContent {
                    Text("Installed automatically")
                } label: {
                    Text(verbatim: "Docker")
                }
            }
        } header: {
            Text("Minimum server requirements")
        } footer: {
            if deployment.services.contains(.gitlab) {
                Text("Minimums for the services you picked. GitLab is by far the heaviest — it alone wants about 8 GB of memory, and a smaller server will not run it.")
            } else {
                Text("Minimums for the services you picked. Mail (mailcow) is the heaviest — a smaller server may run out of memory.")
            }
        }
    }
}
