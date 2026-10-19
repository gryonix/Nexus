import ServerControl
import ServiceCatalog
import SwiftUI
import gryonixNexusCore
#if canImport(UIKit)
import UIKit
#endif

struct ServerFormView: View {
    enum Mode {
        case add
        case edit(Deployment)

        var title: LocalizedStringKey {
            switch self {
            case .add: return "New Server"
            case .edit: return "Server settings"
            }
        }

        var isAdd: Bool {
            if case .add = self { return true }
            return false
        }

        var deployment: Deployment? {
            if case .edit(let deployment) = self { return deployment }
            return nil
        }
    }

    let mode: Mode
    let onSave: (Deployment) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var topology: Topology
    /// Public internet / local network only / behind a tunnel
    @State private var scope: DeploymentScope
    @State private var domain: String
    @State private var host: String
    @State private var port: Int
    @State private var user: String
    @State private var homeWGAddress: String
    @State private var homeLANAddress: String
    @State private var wgInterface: String
    @State private var services: Set<ServiceID>
    @State private var settings: ServiceSettings
    @State private var timeouts: OperationTimeouts
    @State private var tagsText: String
    /// The groups the rest of the fleet is in
    @State private var knownGroups: [String] = ServerGroups.known()
    @State private var namingGroup = false
    @State private var newGroupName = ""
    @State private var metricsIndicatorStyle: MetricsIndicatorStyle?
    @State private var access: ServerAccessOptions
    /// The Wake-on-LAN address, read from the machine
    @State private var wakeOnLANMAC: String
    @State private var fleet: [Deployment] = []
    @State private var usesPasswordAuth: Bool
    @State private var iconSymbol: String?
    @State private var tintName: String?
    @State private var password = ""
    /// The home half's own password
    @State private var homePassword = ""
    @State private var usesAgent: Bool
    @State private var addID = UUID()
    /// This deployment's public key, in `authorized_keys` form
    @State private var publicKey = ""
    @State private var keyError: String?
    @State private var copied: CopiedItem?

    private enum CopiedItem: String, Identifiable {
        case key, command
        var id: String { rawValue }
    }
    @State private var adopting = false

    private enum AddStep { case connection, details }
    @State private var addStep = AddStep.connection
    /// Result of the connection probe on the first page
    @State private var probe = ProbeState.unchecked
    enum ProbeState: Equatable {
        case unchecked, checking, ok, failed(String)
    }
    @State private var adoptedServices: Set<ServiceID>?
    /// What the machine calls itself, from the agent
    @State private var adoptedHostname: String?
    /// What the server says it serves, primary domain first
    @State private var adoptedDomains: [String] = []
    /// The rest of them, kept until Save
    @State private var adoptedAliases: [String] = []

    private let existingID: UUID?

    init(mode: Mode,
         onSave: @escaping (Deployment) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _topology = State(initialValue: .singleHost)
            _scope = State(initialValue: .publicInternet)
            _domain = State(initialValue: "")
            _host = State(initialValue: "")
            _port = State(initialValue: 22)
            _user = State(initialValue: "root")
            _homeWGAddress = State(initialValue: "10.8.0.2")
            _homeLANAddress = State(initialValue: "")
            _wgInterface = State(initialValue: "wg0")
            _services = State(initialValue: [])
            _settings = State(initialValue: ServiceSettings())
            _timeouts = State(initialValue: OperationTimeouts())
            _tagsText = State(initialValue: "")
            _metricsIndicatorStyle = State(initialValue: nil)
            _usesPasswordAuth = State(initialValue: false)
            _access = State(initialValue: .none)
            _wakeOnLANMAC = State(initialValue: "")
            _usesAgent = State(initialValue: false)
            _iconSymbol = State(initialValue: nil)
            _tintName = State(initialValue: nil)
            existingID = nil
        case .edit(let deployment):
            _name = State(initialValue: deployment.name)
            _topology = State(initialValue: deployment.topology)
            _scope = State(initialValue: deployment.scope)
            _domain = State(initialValue: deployment.domain)
            _host = State(initialValue: deployment.entry.host)
            _port = State(initialValue: deployment.entry.port)
            _user = State(initialValue: deployment.entry.user)
            _homeWGAddress = State(initialValue: deployment.homeWGAddress ?? "10.8.0.2")
            _homeLANAddress = State(initialValue:
                InstallAddressStore.homeAddress(deploymentID: deployment.id))
            _wgInterface = State(initialValue: deployment.wgInterface)
            _services = State(initialValue: deployment.services)
            _settings = State(initialValue: deployment.serviceSettings)
            _timeouts = State(initialValue: deployment.timeouts)
            _tagsText = State(initialValue: deployment.tags.joined(separator: ", "))
            _metricsIndicatorStyle = State(initialValue: deployment.metricsIndicatorStyle)
            _usesPasswordAuth = State(initialValue: deployment.usesPasswordAuth)
            _access = State(initialValue: ServerAccessStore.options(for: deployment.id))
            _wakeOnLANMAC = State(initialValue: deployment.wakeOnLANMAC ?? "")
            _usesAgent = State(initialValue: deployment.usesAgent)
            _iconSymbol = State(initialValue: deployment.iconSymbol)
            _tintName = State(initialValue: deployment.tintName)
            existingID = deployment.id
        }
    }

    private var canSave: Bool {
        if usesPasswordAuth, existingID == nil, password.isEmpty { return false }
        if usesPasswordAuth, existingID == nil, topology == .vpsRelayWithHomeBackend,
           homePassword.isEmpty { return false }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
            && HostEndpoint(host: host.trimmingCharacters(in: .whitespaces),
                            port: port,
                            user: user.trimmingCharacters(in: .whitespaces)).isValid
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            Form {
                if mode.isAdd {
                    switch addStep {
                    case .connection: connectionSection
                    case .details: detailsSection; appearanceSection
                    }
                } else {
                    editSections
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            #if DEBUG
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SCROLL"] != nil
                else { return }
                for delay in [700, 2_600] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    withAnimation { scroll.scrollTo("advanced", anchor: .top) }
                }
            }
            #endif
            .navigationTitle(mode.isAdd ? addTitle : mode.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { formToolbar }
            .task { await loadKey() }
            .task {
                fleet = (try? FileDeploymentStore().load()) ?? []
            }
            .safeAreaInset(edge: .bottom) {
                if mode.isAdd { addActionBar }
            }
            .sheet(isPresented: $adopting, onDismiss: handleAdoptionDismiss) {
                if #available(macOS 15.0, *) {
                    AdoptServerSheet(
                        deployment: makeDeployment(),
                        deviceLabel: deviceLabel,
                        onAdopted: { result in
                            adoptedServices = result.serviceIDs
                            adoptedHostname = result.hostname
                            adoptedDomains = result.domains
                        },
                        onCancel: {})
                }
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 600)
            #endif
            }
        }
    }

    private var addTitle: LocalizedStringKey {
        addStep == .connection ? "Connect to the server" : "Name and look"
    }

    @ToolbarContentBuilder
    private var formToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if mode.isAdd, addStep == .details {
                Button("Back") { withAnimation { addStep = .connection } }
            } else {
                Button("Cancel") { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if !mode.isAdd {
                Button("Save") { commit() }
                    .disabled(!canSave)
            }
        }
    }

    private var addActionBar: some View {
        Button {
            switch addStep {
            case .connection:
                if probe == .ok { withAnimation { addStep = .details } } else { runProbe() }
            case .details:
                commit()
            }
        } label: {
            Group {
                switch addStep {
                case .connection: Text(probe == .ok ? "Next" : "Connect")
                case .details: Text("Save")
                }
            }
            .font(.headline)
            .frame(maxWidth: 420)
            .padding(.vertical, 6)
        }
        .prominentActionButtonStyle()
        .controlSize(.large)
        .disabled(addStep == .connection ? (!canConnect || probe == .checking) : !canSave)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var editSections: some View {
        detailsSection
        appearanceSection
        ConnectionSettingsSection()
        connectionSection
        advancedSection
    }

    private var detailsSection: some View {
        Group {
            Section("Server") {
                formField("Name", prompt: "Home mail", text: $name)
                if !mode.isAdd {
                    shapePicker
                }
                formField("Domain", prompt: "example.com", text: $domain)
                groupsRow
                WrappingPicker("Load indicator", selection: $metricsIndicatorStyle) {
                    Text("App default").tag(MetricsIndicatorStyle?.none)
                    Text("Bars").tag(MetricsIndicatorStyle?.some(.bars))
                    Text("Line").tag(MetricsIndicatorStyle?.some(.track))
                    Text("Rings").tag(MetricsIndicatorStyle?.some(.rings))
                    Text("Minimal").tag(MetricsIndicatorStyle?.some(.minimal))
                }
            }
        }
    }

    @ViewBuilder
    private var shapePicker: some View {
        WrappingPicker("Server shape", selection: shapeBinding) {
            ForEach(ScenarioOption.all) { option in
                Text(option.title).tag(option.id)
            }
        }
        if let option = ScenarioOption.all.first(where: { $0.id == shapeBinding.wrappedValue }) {
            Text(option.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One selection writing two stored values
    private var shapeBinding: Binding<String> {
        Binding(
            get: {
                ScenarioOption.all.first { $0.topology == topology && $0.scope == scope }?.id
                    ?? ScenarioOption.all[0].id
            },
            set: { id in
                guard let option = ScenarioOption.all.first(where: { $0.id == id }) else { return }
                topology = option.topology
                scope = option.scope
            }
        )
    }

    /// What the address field is asking for
    private var addressFieldTitle: LocalizedStringKey {
        topology == .vpsRelayWithHomeBackend ? "VPS address" : "Server address"
    }

    private var addressFieldPrompt: LocalizedStringKey {
        scope == .localOnly ? "192.168.1.24" : "203.0.113.4"
    }

    private var connectionSection: some View {
        Group {
            Section {
                if mode.isAdd {
                    shapePicker
                        .onChange(of: topology) { _, _ in probe = .unchecked }
                }
                formField(addressFieldTitle, prompt: addressFieldPrompt, text: $host)
                    .onChange(of: host) { _, _ in probe = .unchecked }
                LabeledContent("Port") {
                    TextField("Port", value: $port, format: .number,
                              prompt: Text(verbatim: "22").foregroundStyle(.secondary))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
                .onChange(of: port) { _, _ in probe = .unchecked }
                formField("User", prompt: "root", text: $user)
                    .onChange(of: user) { _, _ in probe = .unchecked }
                Toggle("Sign in with password", isOn: $usesPasswordAuth)
                    .onChange(of: usesPasswordAuth) { _, _ in probe = .unchecked }
                if usesPasswordAuth {
                    SecureTechnicalField(title: "Password", text: $password)
                        .onChange(of: password) { _, _ in probe = .unchecked }
                }
                if existingID == nil {
                    if #available(macOS 15.0, *) {
                        Button {
                            beginAdoption()
                        } label: {
                            Label("Check for an agent…",
                                  systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .rowActionButtonStyle()
                        .disabled(!canConnect)
                    }
                }
            } header: {
                Text(topology == .vpsRelayWithHomeBackend ? "VPS (SSH)" : "Connection (SSH)")
            } footer: {
                probeFooter
            }

            if !usesPasswordAuth {
                keySection
            }

            if topology == .vpsRelayWithHomeBackend {
                Section {
                    formField("Address in WireGuard", prompt: "10.8.0.2", text: $homeWGAddress)
                    formField("Address on the network", prompt: "192.168.1.50",
                              text: $homeLANAddress)
                    formField("WireGuard interface", prompt: "wg0", text: $wgInterface)
                    if usesPasswordAuth {
                        SecureTechnicalField(title: "Password", text: $homePassword)
                            .onChange(of: homePassword) { _, _ in probe = .unchecked }
                    }
                } header: {
                    InfoSectionHeader("Local server", note: "The app reaches this machine through the VPS over the tunnel. The network address is the way in when the VPS is down — it only works while this device is on the same network, and it is never exported with the server.")
                }
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        AdvancedSection(footer: "These apply to this device only. A server exported to another device does not carry them — a jump host or a wake-up address is a fact about the network you reach it from.") {
            Toggle("SSH agent forwarding", isOn: $access.agentForwarding)
                .disabled(true)
            Text("Not available in this build — the app's SSH library has no agent channel, and a phone runs no agent to forward.")
                .font(.caption)
                .foregroundStyle(.secondary)
            formField("File browser folder", prompt: "/", text: Binding(
                get: { access.sftpDirectory ?? "" },
                set: { access.sftpDirectory = $0.isEmpty ? nil : $0 }
            ))
            NavigationLink {
                BastionPicker(selection: $access.bastion, fleet: fleet, excluding: existingID)
            } label: {
                LabeledContent("Bastion server") {
                    Text(bastionSummary(access.bastion, fleet: fleet))
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                FallbackAddressView(fallback: $access.fallback, fleet: fleet,
                                    excluding: existingID, primary: currentEndpoint)
            } label: {
                LabeledContent("Fallback address") {
                    Text(fallbackSummary(access.fallback))
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                ProxyPickerView(selection: $access.proxyID)
            } label: {
                LabeledContent("Proxy") {
                    Text(proxySummary(access.proxyID)).foregroundStyle(.secondary)
                }
            }
        }
        .id("advanced")
    }

    private var currentEndpoint: HostEndpoint {
        HostEndpoint(host: host.trimmingCharacters(in: .whitespaces),
                     port: port,
                     user: user.trimmingCharacters(in: .whitespaces))
    }

    @ViewBuilder
    private var keySection: some View {
        Section {
            if let keyError {
                Label(keyError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if publicKey.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Preparing the key…").foregroundStyle(.secondary)
                }
            } else {
                Text(verbatim: publicKey)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Button {
                    copy(AccessGrantCommand.command(publicKey: publicKey), as: .command)
                } label: {
                    Label("Copy the command for the server", systemImage: "terminal")
                }
                .rowActionButtonStyle()
                Button {
                    copy(publicKey, as: .key)
                } label: {
                    Label("Copy the public key", systemImage: "doc.on.doc")
                }
                .rowActionButtonStyle()
            }
        } header: {
            Text("App SSH key")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Run the copied command on the server — in the provider's console, or in an SSH session you already have. It adds this key to the account it runs as and prints that account's name; it must be the user above.")
                if let copied {
                    Label(copied == .command ? "Command copied" : "Public key copied",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    /// Copies and says so
    private func copy(_ text: String, as item: CopiedItem) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = item
    }

    /// Reads this server's key, generating it on first sight
    private func loadKey() async {
        let id = existingID ?? addID
        let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
            do { return .success(try KeychainSSHIdentityStore(deploymentID: id).loadOrGenerate().publicKeyOpenSSH) }
            catch { return .failure(error) }
        }.value
        switch result {
        case .success(let key):
            publicKey = key
            keyError = nil
        case .failure(let error):
            keyError = (error as? LocalizedError)?.errorDescription
                ?? UIL10n.string("Could not read the key from the Keychain")
        }
    }

    @ViewBuilder
    private var probeFooter: some View {
        switch probe {
        case .unchecked:
            if mode.isAdd {
                Text("The app signs in over SSH with the key it keeps in this device's Keychain. If the account does not have that key yet, copy the command below and run it on the server first.")
            }
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
            }
        case .ok:
            Label("Connected.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func runProbe() {
        probe = .checking
        let deployment = makeDeployment()
        persistCredentials(for: deployment)
        Task {
            do {
                let runner = try await DashboardSessionFactory.makeRunnerDetached(
                    deployment: deployment, shared: false)
                let result = try await runner.run("echo GRYONIXNEXUS_PING", on: .vps, timeout: .seconds(20))
                await runner.disconnect()
                probe = result.stdout.contains("GRYONIXNEXUS_PING")
                    ? .ok
                    : .failed(UIL10n.string("Unexpected response from the server"))
                if probe == .ok, name.trimmingCharacters(in: .whitespaces).isEmpty {
                    name = host.trimmingCharacters(in: .whitespaces)
                }
            } catch {
                probe = .failed((error as? ServerControlError)?.errorDescription
                                ?? error.localizedDescription)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            LabeledContent("Icon") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        iconButton(nil)
                        ForEach(ServerIcon.choices, id: \.self) { iconButton($0) }
                    }
                    .padding(.vertical, 2)
                }
            }
            LabeledContent("Color") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        colorSwatch(nil)
                        ForEach(ServerTint.allCases) { colorSwatch($0) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var previewTint: Color { tintName.flatMap { ServerTint(rawValue: $0)?.color } ?? .accentColor }

    @ViewBuilder
    private func iconButton(_ symbol: String?) -> some View {
        let isSelected = iconSymbol == symbol
        Button {
            iconSymbol = symbol
        } label: {
            Image(systemName: symbol ?? ServerIcon.defaultSymbol)
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .foregroundStyle(isSelected ? Color.white : previewTint)
                .background(isSelected ? previewTint : Color.secondary.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol ?? "Default")
    }

    @ViewBuilder
    private func colorSwatch(_ tint: ServerTint?) -> some View {
        let isSelected = tintName == tint?.rawValue
        Button {
            tintName = tint?.rawValue
        } label: {
            ZStack {
                Circle()
                    .fill(tint?.color ?? Color.accentColor)
                    .frame(width: 28, height: 28)
                if tint == nil {
                    Image(systemName: "a.circle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                if isSelected {
                    Circle().strokeBorder(Color.primary, lineWidth: 2).frame(width: 34, height: 34)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tint?.rawValue ?? "Default")
    }

    private func makeDeployment() -> Deployment {
        Deployment(
            id: existingID ?? addID,
            name: name.trimmingCharacters(in: .whitespaces),
            topology: topology,
            domain: domain.trimmingCharacters(in: .whitespaces).lowercased(),
            additionalDomains: mode.deployment?.additionalDomains ?? adoptedAliases,
            entry: HostEndpoint(host: host.trimmingCharacters(in: .whitespaces),
                                port: port,
                                user: user.trimmingCharacters(in: .whitespaces)),
            homeWGAddress: topology == .vpsRelayWithHomeBackend
                ? homeWGAddress.trimmingCharacters(in: .whitespaces) : nil,
            wgInterface: wgInterface.trimmingCharacters(in: .whitespaces),
            services: services,
            serviceSettings: settings,
            timeouts: timeouts,
            tags: parsedTags,
            metricsIndicatorStyle: metricsIndicatorStyle,
            usesPasswordAuth: usesPasswordAuth,
            usesAgent: usesAgent,
            iconSymbol: iconSymbol,
            tintName: tintName,
            scope: scope,
            wakeOnLANMAC: WakeOnLAN.normalised(wakeOnLANMAC)
        )
    }

    private var canConnect: Bool {
        if usesPasswordAuth, password.isEmpty { return false }
        return HostEndpoint(host: host.trimmingCharacters(in: .whitespaces),
                            port: port,
                            user: user.trimmingCharacters(in: .whitespaces)).isValid
    }

    private func persistCredentials(for deployment: Deployment) {
        let store = DashboardPasswordStore(deploymentID: deployment.id)
        if usesPasswordAuth {
            if !password.isEmpty {
                try? store.save(password, for: .vps)
            }
            if topology == .vpsRelayWithHomeBackend, !homePassword.isEmpty {
                try? store.save(homePassword, for: .home)
            }
        } else {
            store.delete(nodeIDs: deployment.nodes.map(\.id))
        }
        InstallAddressStore.save(
            homeAddress: homeLANAddress.trimmingCharacters(in: .whitespaces),
            deploymentID: deployment.id)
        ServerAccessStore.save(trimmedAccess, for: deployment.id)
    }

    private var trimmedAccess: ServerAccessOptions {
        var options = access
        let folder = (options.sftpDirectory ?? "").trimmingCharacters(in: .whitespaces)
        options.sftpDirectory = folder.isEmpty ? nil : folder
        if let fallback = options.fallback, !fallback.isUsable { options.fallback = nil }
        return options
    }

    private func commit() {
        let deployment = makeDeployment()
        persistCredentials(for: deployment)
        onSave(deployment)
        dismiss()
    }

    private func beginAdoption() {
        persistCredentials(for: makeDeployment())
        adopting = true
    }

    private var deviceLabel: String {
        if #available(macOS 15.0, *) { return AgentDeviceEnrolment.deviceLabel }
        return "Device"
    }

    /// Runs after the adoption sheet is fully dismissed
    private func handleAdoptionDismiss() {
        if let discovered = adoptedServices {
            adoptedServices = nil
            services = discovered
            usesAgent = true
            if name.trimmingCharacters(in: .whitespaces).isEmpty,
               let hostname = adoptedHostname?.trimmingCharacters(in: .whitespaces),
               !hostname.isEmpty {
                name = hostname
            }
            if domain.trimmingCharacters(in: .whitespaces).isEmpty,
               let primary = adoptedDomains.first {
                domain = primary
            }
            adoptedAliases = Array(adoptedDomains.dropFirst())
            adoptedHostname = nil
            adoptedDomains = []
            withAnimation { addStep = .details }
        } else {
            DashboardPasswordStore(deploymentID: addID).delete()   // staged add: no nodes exist yet
            InstallAddressStore.save(homeAddress: "", deploymentID: addID)
        }
    }

    private var groupsRow: some View {
        LabeledContent("Groups") {
            Menu {
                ForEach(offeredGroups, id: \.self) { group in
                    Toggle(isOn: Binding(get: { isMember(of: group) },
                                         set: { _ in toggle(group: group) })) {
                        Text(verbatim: group)
                    }
                }
                if !offeredGroups.isEmpty { Divider() }
                Button {
                    newGroupName = ""
                    namingGroup = true
                } label: {
                    Label("New group…", systemImage: "plus")
                }
            } label: {
                Text(parsedTags.isEmpty ? UIL10n.string("None") : parsedTags.joined(separator: ", "))
                    .lineLimit(1)
            }
        }
        .alert("New group", isPresented: $namingGroup) {
            TextField("Group", text: $newGroupName)
            Button("Add") {
                if let name = ServerGroups.clean(newGroupName), !isMember(of: name) {
                    toggle(group: name)
                }
                namingGroup = false
            }
            Button("Cancel", role: .cancel) { namingGroup = false }
        }
    }

    private var offeredGroups: [String] {
        var seen = Set<String>()
        return (knownGroups + parsedTags).filter { seen.insert($0.lowercased()).inserted }
    }

    private func isMember(of group: String) -> Bool {
        parsedTags.contains { $0.caseInsensitiveCompare(group) == .orderedSame }
    }

    private func toggle(group: String) {
        let tags = ServerGroups.setting(!isMember(of: group), of: group, in: parsedTags)
        tagsText = tags.joined(separator: ", ")
    }

    /// Comma-separated input → clean unique tags, original order kept
    private var parsedTags: [String] {
        var seen = Set<String>()
        return tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private func formField(_ title: LocalizedStringKey, prompt: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent {
            #if os(macOS)
            TextField(title, text: text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .overlay(alignment: .trailing) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt)
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
            #else
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(.secondary))
                .labelsHidden()
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            #endif
        } label: {
            Text(title)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

#Preview {
    ServerFormView(mode: .add) { _ in }
}
