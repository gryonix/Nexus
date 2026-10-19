import gryonixNexusCore
import ServerControl
import ServiceCatalog
import SwiftUI

/// The configurator: pick the scenario, then walk a one-question-per-screen setup
struct SimpleConfiguratorView: View {
    var body: some View {
        CardList {
            ForEach(ScenarioOption.all) { option in
                NavigationLink {
                    SimpleWizardView(topology: option.topology, scope: option.scope)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: option.systemImage)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title).font(.headline)
                            Text(option.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Configurator")
    }
}

/// The setup itself
struct SimpleWizardView: View {
    @StateObject private var viewModel: ServiceConfigViewModel
    @State private var dismiss = DismissHandle()
    @State private var index = 0
    @State private var didPrepare = false
    @State private var showHistory = false
    /// The category whose product list is open, if any
    @State private var picking: ServiceCategory?
    /// The protocol whose comparison sheet is open, if any
    @State private var protocolInfo: VPNProtocolInfo?
    private let isRestoring: Bool

    init(topology: Topology, scope: DeploymentScope = .publicInternet,
         restoring config: ConfiguratorDraft? = nil,
         existingServer: Deployment? = nil) {
        _viewModel = StateObject(wrappedValue: ServiceConfigViewModel(topology: topology,
                                                                      initialScope: scope,
                                                                      restoringConfig: config,
                                                                      existingServer: existingServer))
        isRestoring = config != nil
    }

    private enum Step: Hashable {
        case services, vpnProtocol, domain, address, admin, dns, review
    }

    @State private var acknowledged: Set<Step> = []
    @State private var standingOnVPNStep = false

    private var steps: [Step] {
        var s: [Step] = [.services]
        if viewModel.vpnEnabled || standingOnVPNStep { s.append(.vpnProtocol) }
        if viewModel.localOnly {
            s.append(.address)
        } else {
            s.append(contentsOf: [.domain, .address])
        }
        if viewModel.hasAdminService { s.append(.admin) }
        if viewModel.scope.publishesAddressRecords { s.append(.dns) }
        s.append(.review)
        return s
    }

    private var current: Step { steps[min(index, steps.count - 1)] }

    private var showResult: Binding<Bool> {
        Binding(get: { viewModel.bundle != nil },
                set: {
                    #if DEBUG
                    if !$0 { InstallResetProbe.note("showResult set to false — clearing viewModel.bundle", trace: true) }
                    #endif
                    if !$0 { viewModel.bundle = nil }
                })
    }

    var body: some View {
        screen.dismissHandle(dismiss)
    }

    @ViewBuilder private var screen: some View {
        ScrollViewReader { scroller in
            debugTasks(sheets(chrome), scroller: scroller)
        }
    }

    private var chrome: some View {
        Form {
            switch current {
            case .services: servicesStep
            case .vpnProtocol: vpnStep
            case .domain: domainStep
            case .address: addressStep
            case .admin: adminStep
            case .dns: dnsStep
            case .review: reviewStep
            }
        }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Setup")
            .raisedNavigationTitle()
            .onChange(of: current, initial: true) { _, step in
                if step == .vpnProtocol { standingOnVPNStep = true }
            }
            .task { await viewModel.prefillStoredPassword() }
            .navigationBarBackButtonHidden(true)
            .toolbar { wizardToolbar }
            .safeAreaInset(edge: .bottom) { navigationBar }
            .ownsBottomEdge()
            .domainChangeAlert(viewModel: viewModel)
    }

    @ToolbarContentBuilder
    private var wizardToolbar: some ToolbarContent {
        ToolbarItem(placement: .wizardBack) {
            Button {
                if current == .vpnProtocol { standingOnVPNStep = false }
                if index > 0 { withAnimation { index -= 1 } } else { dismiss() }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private func sheets(_ base: some View) -> some View {
        base
            .sheet(item: $picking) { category in
                ServicePickerSheet(category: category,
                                   scope: viewModel.scope,
                                   selected: viewModel.selectedServices,
                                   binding: { viewModel.serviceBinding($0) },
                                   note: { Self.serviceNote(for: $0) })
            }
            .sheet(item: $protocolInfo) { info in
                VPNProtocolInfoView(info: info)
            }
            .sheet(isPresented: $showHistory) {
                ConfiguratorHistoryView(
                    topology: viewModel.topology,
                    scope: viewModel.scope,
                    entries: viewModel.historyEntries(),
                    onRestore: { viewModel.apply($0) },
                    onDelete: { viewModel.deleteHistoryEntries(ids: $0) }
                )
            }
            .navigationDestination(isPresented: showResult) {
                if let bundle = viewModel.bundle {
                    SimpleResultView(bundle: bundle, deployment: viewModel.savedDeployment,
                                     openPorts: viewModel.openPorts)
                }
            }
            .task {
                guard !didPrepare, !isRestoring else { return }
                didPrepare = true
                viewModel.includeDashboardAccess = true
            }
    }

    @ViewBuilder
    private func debugTasks(_ base: some View, scroller: ScrollViewProxy) -> some View {
        #if DEBUG
        base
            .task {
                guard InstallResetProbe.autoDrive else { return }
                viewModel.scope = .localOnly
                viewModel.includeDashboardAccess = true
                viewModel.dashboardSSHUser = "control"
                viewModel.publicIP = "192.168.1.50"
                viewModel.domain = "192.168.1.50"
                if let target = steps.firstIndex(of: .review) { index = target }
                await viewModel.generate()
                InstallResetProbe.note("auto-drive: generate() done, bundle=\(viewModel.bundle != nil) deployment=\(viewModel.savedDeployment != nil)")
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_LOCALONLY_STEP"] == "address",
                      let target = steps.firstIndex(of: .address) else { return }
                index = target
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_LOCALONLY_STEP"] == "generate" else { return }
                viewModel.includeDashboardAccess = false
                viewModel.publicIP = "192.168.1.50"
                viewModel.domain = "192.168.1.50"
                await viewModel.generate()
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_LOCALONLY_STEP"] == "generate-mail-rejected",
                      let target = steps.firstIndex(of: .review) else { return }
                index = target
                viewModel.includeDashboardAccess = false
                viewModel.publicIP = "192.168.1.50"
                viewModel.domain = "192.168.1.50"
                viewModel.mailEnabled = true
                await viewModel.generate()
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_DNS_STEP"] == "1",
                      let target = steps.firstIndex(of: .dns) else { return }
                viewModel.publicIP = "203.0.113.4"
                viewModel.domain = "example.com"
                index = target
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_NVIDIA_CROWDSEC_STEP"] == "1"
                else { return }
                viewModel.setSelectionPublic([.ollama], in: .ai)
                viewModel.ollamaUsesGPU = true
                viewModel.ollamaInstallsGPUDriver = true
                viewModel.includeDashboardAccess = true
                viewModel.crowdsecEnabled = false
            }
            .task(id: current) {
                let section = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_CONFIG_SECTION"]
                guard let anchor = section.flatMap(Anchor.init(rawValue:)), current == .services else { return }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation { scroller.scrollTo(anchor, anchor: .center) }
            }
        #else
        base
        #endif
    }

    private enum Anchor: String, Hashable { case agent, sso }

    // MARK: - Steps

    private var servicesStep: some View {
        Group {
            categoriesSection
            modelsSection
            questionsSection
            advancedServicesSection
            agentAccessSection
        }
    }

    private var categoriesSection: some View {
        Section {
            ForEach(viewModel.availableCategories) { category in
                categoryToggle(category)
                if enginePicker(for: category) {
                    Button {
                        picking = category
                    } label: {
                        LabeledContent(LocalizedStringKey(category.title)) {
                            HStack(spacing: 4) {
                                Text(verbatim: chosenNames(in: category))
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                categoryWarning(for: category)
            }
        } header: {
            InfoSectionHeader("What do you want?", note: "Turn on what you need. Each one installs and configures itself — passwords are shown at the end.")
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        if aiShelfIsOn {
            Section {
                Picker("Where the models run", selection: $viewModel.modelBackend) {
                    Text("On this server").tag(ModelBackend.here)
                    if viewModel.topology == .vpsRelayWithHomeBackend {
                        Text("On the local server at home").tag(ModelBackend.home)
                    }
                    Text("Somebody else's API").tag(ModelBackend.external)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Label(modelBackendCost, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.modelBackend != .external {
                    Toggle("Use the NVIDIA graphics card", isOn: $viewModel.ollamaUsesGPU)
                    Label(gpuCost, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.ollamaUsesGPU {
                        Toggle("Install the NVIDIA driver", isOn: $viewModel.ollamaInstallsGPUDriver)
                        Label(driverInstallCost, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Where do the models run?")
            }
            .onChange(of: viewModel.topology) { _, topology in
                if viewModel.modelBackend == .home, topology != .vpsRelayWithHomeBackend {
                    viewModel.modelBackend = .here
                }
            }
        }
    }

    @ViewBuilder
    private var questionsSection: some View {
        if !questions.isEmpty {
            Section {
                ForEach(questions) { question in
                    Toggle(question.title, isOn: viewModel.questionBinding(question))
                    if !viewModel.isAnswered(question) {
                        Label(question.refusal, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Before this can be installed")
            }
        }
    }

    @ViewBuilder
    private var advancedServicesSection: some View {
        if !advancedServices.isEmpty {
            AdvancedSection {
                ForEach(advancedServices, id: \.self) { id in
                    ServiceAdvancedFields(viewModel: viewModel, id: id)
                }
            }
        }
    }

    private var agentAccessSection: some View {
        Section {
            Toggle(isOn: $viewModel.includeDashboardAccess) {
                Label("Agent access", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
            if viewModel.includeDashboardAccess {
                AdvancedRow("Advanced agent setup",
                            footer: viewModel.useExistingUser
                            ? "The existing user is neither created nor modified — the script only installs the agent's sudoers whitelist for it. The app signs in with this password; it is stored only in the device's Keychain."
                            : "The scripts create a dedicated control user (server-user by default) with SSH-key-only login and rights limited strictly to the agent's commands via sudoers; the server will appear in the Servers tab. The private key stays in the device's Keychain.") {
                    Toggle("Use an existing user", isOn: $viewModel.useExistingUser)
                    TechnicalField(title: "SSH user",
                                   prompt: viewModel.useExistingUser ? "user" : "server-user",
                                   text: $viewModel.dashboardSSHUser)
                    if viewModel.useExistingUser {
                        SecureTechnicalField(
                            title: viewModel.topology == .vpsRelayWithHomeBackend ? "Password (VPS)" : "Password",
                            text: $viewModel.existingUserPassword)
                        if viewModel.topology == .vpsRelayWithHomeBackend {
                            SecureTechnicalField(title: "Password (local server)",
                                                 text: $viewModel.existingUserHomePassword)
                        }
                    }
                }
            }
        } header: {
            InfoSectionHeader("Agent access", note: "Lets you manage this server from the app (Servers tab) and install it straight from this device.")
        }
        .id(Anchor.agent)
    }

    /// True once anything on the AI shelf is chosen
    private var aiShelfIsOn: Bool {
        !viewModel.selection(in: .ai).isEmpty
    }

    private var modelBackendCost: LocalizedStringKey {
        switch viewModel.modelBackend {
        case .here:
            return "A model engine is installed on this server. Without a graphics card a small model answers at a few words a second, and each model is 4–40 GB of disk."
        case .home:
            return "The engine goes on the machine at home, where a graphics card can do the work; this server only relays."
        case .external:
            return "Nothing runs here. The chat calls a provider you have an API key for, and every message leaves the server."
        }
    }

    private var gpuCost: LocalizedStringKey {
        guard viewModel.ollamaUsesGPU else {
            return "The engine runs on the processor. On a server without a graphics card that is a few words a second for a small model."
        }
        return viewModel.ollamaInstallsGPUDriver
            ? "The install adds NVIDIA's container toolkit and restarts docker once — every container on that server restarts with it."
            : "The install adds NVIDIA's container toolkit and restarts docker once — every container on that server restarts with it. The DRIVER is not installed: if the machine has none, the engine runs on the processor and the report says so."
    }

    private var driverInstallCost: LocalizedStringKey {
        "Installs the driver with `ubuntu-drivers autoinstall` if none answers. It does NOT reboot the server — the card only starts answering after one, and the report says so. If Secure Boot is on, the install refuses rather than leave the machine waiting at an enrollment screen nobody is at; turn it off first, or install the driver yourself."
    }

    private var questions: [ServiceQuestion] {
        ServiceQuestions.raised(by: viewModel.selectedServices,
                                topology: viewModel.topology, scope: viewModel.scope)
    }

    private var advancedServices: [ServiceID] {
        viewModel.availableCategories
            .filter { $0 != .vpn }
            .flatMap { category in
                ServiceRegistry.selection(in: category, from: viewModel.selection(in: category))
            }
            .filter { ServiceAdvancedFields.hasFields(for: $0) }
    }

    private var vpnStep: some View {
        Group {
            Section {
                WrappingPicker("VPN configs", selection: $viewModel.vpnClientAccess) {
                    Text("In the app and the panel").tag(VPNClientAccess.both)
                    Text("In the app only").tag(VPNClientAccess.app)
                    Text("In the panel only").tag(VPNClientAccess.panel)
                }
                if viewModel.vpnClientAccess == .app {
                    Label("The panel keeps running, but its page is not published — no vpn address, no certificate, no login form on the internet. Devices are added from the app, which needs the agent installed on the server.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(isOn: Binding(
                    get: { viewModel.allVPNProtocolsSelected },
                    set: { viewModel.setAllVPNProtocols($0) }
                )) {
                    Label("All protocols", systemImage: "square.stack.3d.up")
                }
                ForEach(ServiceConfigViewModel.allVPNProtocols, id: \.self) { proto in
                    Toggle(isOn: viewModel.vpnProtocolBinding(proto)) {
                        HStack(spacing: 6) {
                            Label(viewModel.serviceDisplayName(proto),
                                  systemImage: viewModel.serviceSystemImage(proto))
                            Button {
                                protocolInfo = VPNProtocolInfo.info(for: proto)
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.tint)
                            }
                            .glassIconButtonStyle()
                            .accessibilityLabel(Text(viewModel.serviceDisplayName(proto)))
                        }
                    }
                }
            } header: {
                InfoSectionHeader("Which VPN?", note: "Pick one or more. They all share one address and one panel — WireGuard works well on most devices. Keep WireGuard: the admin panels (mail, cloud, photos, vault) open only over it, the other protocols carry internet traffic only.")
            }

            if !viewModel.selection(in: .vpn).isEmpty {
                AdvancedSection {
                    TechnicalField(title: "VPN domain",
                                   prompt: viewModel.vpnHostnamePlaceholder,
                                   text: $viewModel.vpnHostname, ownAddress: true)
                    ForEach(ServiceConfigViewModel.allVPNProtocols, id: \.self) { proto in
                        if viewModel.selection(in: .vpn).contains(proto) {
                            VPNProtocolAdvancedFields(viewModel: viewModel, proto: proto)
                        }
                    }
                }
            }
        }
    }

    private var domainStep: some View {
        Group {
            Section {
                TechnicalField(title: "Primary domain", prompt: "example.com", text: $viewModel.domain,
                               ownAddress: true)
                ForEach(viewModel.additionalDomains.indices, id: \.self) { index in
                    TechnicalField(title: "Additional domain", prompt: "second.org",
                                   text: Binding(
                                    get: { viewModel.additionalDomains[index] },
                                    set: { viewModel.additionalDomains[index] = $0 }),
                                   ownAddress: true)
                }
                .onDelete { viewModel.additionalDomains.remove(atOffsets: $0) }
                if viewModel.canAddDomain {
                    Button {
                        if LicensePrompt.shared.allow() { viewModel.additionalDomains.append("") }
                    } label: {
                        Label("Add domain", systemImage: "plus")
                    }
                    .rowActionButtonStyle()
                }
            } header: {
                InfoSectionHeader("Your domain", note: "The domain name your services will use, e.g. example.com. You can add more — every service answers on all of them, and with mail each gets its own mailboxes. Swipe a domain to remove it.")
            }
        }
        .onAppear { viewModel.useDemoAddressesIfLocked() }
    }

    private var addressStep: some View {
        Group {
        Section {
            TechnicalField(title: viewModel.localOnly ? "Local address"
                              : (viewModel.topology == .singleHost ? "Server address" : "VPS address"),
                           prompt: viewModel.localOnly ? "192.168.1.50" : "203.0.113.10",
                           text: viewModel.localOnly ? localAddressBinding : $viewModel.publicIP,
                           ownAddress: true)
            DistributionPicker(
                title: viewModel.topology == .singleHost
                    ? "Server distribution" : "VPS distribution",
                selection: $viewModel.distribution)
            if viewModel.topology == .vpsRelayWithHomeBackend {
                TechnicalField(title: "Local server on your network", prompt: "192.168.1.50",
                               text: $viewModel.homeNetworkAddress, ownAddress: true)
                DistributionPicker(title: "Local server distribution",
                                   selection: $viewModel.homeDistribution)
            }
        } header: {
            Text("Your server")
        } footer: {
            if viewModel.localOnly {
                Text("A LAN IP address or a .local hostname your devices can already reach — not a domain you'd register (like example.com). This is both the server's address and its Caddy site name, self-signed.")
            } else {
                Text(viewModel.topology == .singleHost
                     ? "The public IP address of your server."
                     : "The public IP address of your VPS, and the local server's address on your network — an IP or a .local name. Keep this device on that network while installing.")
            }
        }

        if viewModel.scope == .publicInternet || viewModel.topology == .vpsRelayWithHomeBackend {
            AdvancedSection {
                if viewModel.scope == .publicInternet {
                    TechnicalField(title: "Reverse DNS",
                                   prompt: viewModel.reverseDNSPlaceholder,
                                   text: $viewModel.reverseDNSHostname, ownAddress: true)
                }
                if viewModel.topology == .vpsRelayWithHomeBackend {
                    TechnicalField(title: "VPS address", prompt: "10.8.0.1",
                                   text: $viewModel.vpsVPNIP)
                    TechnicalField(title: "Local server address", prompt: "10.8.0.2",
                                   text: $viewModel.homeVPNIP)
                }
            }
        }
        }
        .onAppear { viewModel.useDemoAddressesIfLocked() }
    }

    private var localAddressBinding: Binding<String> {
        Binding(
            get: { viewModel.publicIP },
            set: { viewModel.publicIP = $0; viewModel.domain = $0 }
        )
    }

    private var adminStep: some View {
        Section {
            TechnicalField(title: "Admin username", prompt: "admin", text: $viewModel.adminUsername)
        } header: {
            InfoSectionHeader("Admin", note: "The admin password is generated on the server and shown at the end.")
        }
    }

    private var dnsStep: some View {
        let zones = viewModel.dnsPreview()
        return Group {
            Section {
                Text("Add these records at your domain provider. Until they exist and have spread, nothing on your domain will work.")
                if viewModel.scope.maintainsItsOwnDNSRecords {
                    Label("Create them once. This server then keeps them pointing at its current address by itself — switch that on from the server's own screen after the install, with a provider token.",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                }
            } header: {
                Text("DNS records")
            }

            if zones.isEmpty {
                Section {
                    Text("Fill in the domain and the server address to see the exact records.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(zones) { zone in
                    zoneSection(zone, showHeading: zones.count > 1,
                                isLast: zone.domain == zones.last?.domain)
                }
            }

            if !zones.isEmpty {
                DNSProviderPublishSection(zones: zones) {
                    acknowledged.insert(.dns)
                }
            }

            Section {
                checkpoint(.dns, title: "I know where to add my DNS records")
            }
        }
    }

    @ViewBuilder
    private func zoneSection(_ zone: ServiceConfigViewModel.DNSZonePreview,
                             showHeading: Bool, isLast: Bool) -> some View {
        Section {
            RecordShareButtons(copyText: recordsText(zone.records, in: zone.domain),
                               zoneFile: zone.zoneFile,
                               csvFile: zone.csvFile)
        } header: {
            if showHeading { Text(verbatim: zone.domain) }
        } footer: {
            if isLast {
                Text("Cloudflare: DNS → Records → “Import and Export” → “Import DNS records” → upload the zone file (Cloudflare accepts only that one, not the CSV). Then set every record to “DNS only” (grey cloud) — the orange cloud breaks mail and the VPN. The CSV is for panels that import a spreadsheet instead.")
            }
        }
    }

    private func nameField(for name: String, in domain: String) -> String {
        guard !domain.isEmpty else { return name }
        if name == domain { return "@" }
        if name.hasSuffix(".\(domain)") { return String(name.dropLast(domain.count + 1)) }
        return name
    }

    private func recordsText(_ records: [DNSRecord], in domain: String) -> String {
        records.map { record in
            let priority = record.priority.map { " \($0)" } ?? ""
            return "\(record.type.rawValue.uppercased())\t\(nameField(for: record.name, in: domain))\t\(record.value)\(priority)"
        }.joined(separator: "\n")
    }

    private func checkpoint(_ step: Step, title: LocalizedStringKey) -> some View {
        Toggle(isOn: Binding(
            get: { acknowledged.contains(step) },
            set: { on in
                if on { acknowledged.insert(step) } else { acknowledged.remove(step) }
            }
        )) {
            Text(title)
        }
    }

    @ViewBuilder private var reviewStep: some View {
        Section {
            if !viewModel.localOnly {
                summaryRow("Domain", viewModel.domain.isEmpty ? "—" : viewModel.domain)
            }
            summaryRow(viewModel.localOnly ? "Local address"
                        : (viewModel.topology == .singleHost ? "Server address" : "VPS address"),
                       viewModel.publicIP.isEmpty ? "—" : viewModel.publicIP)
            if viewModel.isPairTopology {
                summaryRow("Local server on your network",
                           viewModel.homeNetworkAddress.isEmpty ? "—" : viewModel.homeNetworkAddress)
            }
            summaryRow("Services", servicesSummary)
        } header: {
            Text("Review")
        } footer: {
            if let message = viewModel.errorMessage {
                Text(message).foregroundStyle(.red)
            }
        }

        Section {
            Toggle(isOn: $viewModel.crowdsecEnabled) {
                Label("Protect this server", systemImage: "checkmark.shield")
            }
        } header: {
            InfoSectionHeader("Security", note: "CrowdSec watches this server's own login and web logs and blocks the addresses behind repeated attacks — brute-force, scanning, known-bad hosts — and enforces a blocklist shared by every CrowdSec install. Off by choice only: leaving a server unwatched is what this question exists to ask about first.")
        }
    }

    private func summaryRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        #if os(macOS)
        LabeledContent(title) { Text(verbatim: value).foregroundStyle(.secondary) }
        #else
        AdaptiveRow(title) { _ in Text(verbatim: value).foregroundStyle(.secondary) }
        #endif
    }

    private var servicesSummary: String {
        let names = ServiceRegistry.categories
            .filter { !viewModel.selection(in: $0).isEmpty }
            .map { UIL10n.string($0.title) }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        Button {
            if current == .review {
                Task { await viewModel.generate() }
            } else {
                advance()
            }
        } label: {
            Text(current == .review ? "Generate" : "Next")
                .font(.headline)
                .frame(maxWidth: 420)
                .padding(.vertical, 6)
        }
        .prominentActionButtonStyle()
        .controlSize(.large)
        .disabled(!canAdvance)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func advance() {
        if current == .vpnProtocol { standingOnVPNStep = false }
        withAnimation { index += 1 }
    }

    private var canAdvance: Bool {
        switch current {
        case .services: return questions.allSatisfy { viewModel.isAnswered($0) }
        case .vpnProtocol: return !viewModel.vpnProtocols.isEmpty
        case .domain: return !viewModel.domain.trimmingCharacters(in: .whitespaces).isEmpty
        case .address: return !viewModel.publicIP.trimmingCharacters(in: .whitespaces).isEmpty
        case .dns: return acknowledged.contains(current)
        default: return true
        }
    }

    // MARK: - Bindings

    private func enginePicker(for category: ServiceCategory) -> Bool {
        category != .vpn
            && ServiceRegistry.services(in: category).count > 1
            && !viewModel.selection(in: category).isEmpty
    }

    private func chosenNames(in category: ServiceCategory) -> String {
        let chosen = viewModel.selection(in: category)
        let names = ServiceRegistry.services(in: category)
            .filter { chosen.contains($0.id) }
            .map(\.displayName)
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    @ViewBuilder
    private func categoryToggle(_ category: ServiceCategory) -> some View {
        let toggle = Toggle(isOn: viewModel.categoryBinding(category)) {
            categoryLabel(category)
        }
        if category == .singleSignOn {
            toggle.id(Anchor.sso)
        } else {
            toggle
        }
    }

    /// The category's label, with an "i" where it needs explaining
    @ViewBuilder
    private func categoryLabel(_ category: ServiceCategory) -> some View {
        if category == .singleSignOn {
            ServiceCategoryLabel(category: category)
                .infoNote(LocalizedStringKey(category.title), Self.autheliaNote)
        } else {
            ServiceCategoryLabel(category: category)
        }
    }

    static let autheliaNote: LocalizedStringKey = "Authelia asks for one shared login before the sites you choose. By default these are only the services without a login of their own: the start page, AdGuard Home, Pi-hole and Crafty.\n\nServices with their own phone or desktop apps — Vaultwarden, Nextcloud, mailcow and others — stay outside it. Those apps sign in with their own account and cannot pass a web login, so they would stop connecting. Their websites still ask for their own password.\n\nTo put more behind it, open Authelia under Advanced below and switch on the services you want."

    static func serviceNote(for id: ServiceID) -> LocalizedStringKey? {
        switch id {
        case .gitlab:
            return "Needs about 8 GB of memory on its own and several minutes for its first start. Forgejo is the same git hosting on a fraction of that."
        case .adguardHome:
            return "Works from anywhere: it serves the filter over DNS-over-HTTPS through the same HTTPS name as its panel."
        case .pihole:
            return "Serves plain DNS only — right for a machine on your own network, which your router points at. Devices elsewhere need AdGuard Home instead."
        default:
            return nil
        }
    }

    @ViewBuilder
    private func categoryWarning(for category: ServiceCategory) -> some View {
        let selected = viewModel.selection(in: category)
        if selected.contains(.gitlab) {
            Label("GitLab needs about 8 GB of memory — tap to pick Forgejo instead.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if selected.contains(.ollama), selected.isDisjoint(with: ServiceID.modelConsumers) {
            Label("Ollama runs models but has no web page of its own. Add Open WebUI to chat with them from a browser.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    func domainChangeAlert(viewModel: ServiceConfigViewModel) -> some View {
        alert("Change the server's domain?", isPresented: Binding(
            get: { viewModel.pendingDomainChange },
            set: { viewModel.pendingDomainChange = $0 }
        )) {
            Button("Cancel", role: .cancel) {}
            if viewModel.reinstallRecreatesMail {
                Button("Keep mail data") {
                    Task { await viewModel.confirmDomainChangeAndGenerate(erasingMail: false) }
                }
                Button("Erase mail data", role: .destructive) {
                    Task { await viewModel.confirmDomainChangeAndGenerate(erasingMail: true) }
                }
                .dangerTint()
            } else {
                Button("Reinstall", role: .destructive) {
                    Task { await viewModel.confirmDomainChangeAndGenerate(erasingMail: false) }
                }
                .dangerTint()
            }
        } message: {
            if viewModel.reinstallRecreatesMail {
                Text("This server is installed on \(viewModel.reinstallPreviousDomain). Other services keep their data and move to the new domain either way.\n\n**Keep mail data** — mail stays exactly as it is and the new domain is added to it, so both domains receive mail.\n\n**Erase mail data** — mail is installed again for the new domain. **All mailboxes and messages on this server are deleted permanently.**\n\nAdd the DNS records for the new domain before continuing.")
            } else {
                Text("This server is installed on \(viewModel.reinstallPreviousDomain). Services keep their data and start answering on the new domain. Add its DNS records before continuing.")
            }
        }
    }
}
