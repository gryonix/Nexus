import gryonixNexusCore
import ServerControl
import ServerControlSSH
import ServiceCatalog
import SwiftUI

struct ReinstallRequest: Identifiable {
    let id = UUID()
    let deployment: Deployment
    let draft: ConfiguratorDraft
    let editFirst: Bool
}

/// Sheet root for the reinstall flow
struct ReinstallFlowView: View {
    let request: ReinstallRequest

    @Environment(\.dismiss) private var dismiss
    /// Set by "Edit full configuration"
    @State private var editingFullConfig = false

    var body: some View {
        NavigationStack {
            if request.editFirst || editingFullConfig {
                editRoot
            } else {
                ReinstallReviewView(request: request,
                                    onEditFullConfig: { editingFullConfig = true })
                    .toolbar { cancelItem }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .onReceive(AppNavigator.shared.$openServerID.dropFirst().compactMap { $0 }) { _ in
            dismiss()
        }
    }

    private var editRoot: some View {
        SimpleWizardView(topology: request.deployment.topology, restoring: request.draft,
                         existingServer: request.deployment)
    }

    private var cancelItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }
}

private struct ReinstallReviewView: View {
    let request: ReinstallRequest
    let onEditFullConfig: () -> Void

    @StateObject private var viewModel: ServiceConfigViewModel
    @State private var showInstall = false
    @State private var choosingMethod = false
    @State private var removalPrompt: ServiceRemovalPrompt?
    @State private var operation: LongOperationState?
    @State private var continueAfterRemoval = false
    /// Why Continue could not go on
    @State private var failure: String?

    /// What the server carries right now
    private let installed: Set<ServiceID>

    init(request: ReinstallRequest, onEditFullConfig: @escaping () -> Void) {
        self.request = request
        self.onEditFullConfig = onEditFullConfig
        self.installed = request.deployment.services
        _viewModel = StateObject(wrappedValue: ServiceConfigViewModel(
            topology: request.deployment.topology, restoringConfig: request.draft))
    }

    var body: some View {
        Form {
            summarySection
            servicesSection
            errorAndConfigSections
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("Reinstall")
        .task { await viewModel.prefillStoredPassword() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) { continueButton }
        .alert("Remove this service from the server?",
               isPresented: Binding(get: { removalPrompt != nil },
                                                 set: { if !$0 { removalPrompt = nil } }),
                            presenting: removalPrompt) { prompt in
            Button("Remove", role: .destructive) {
                prompt.apply()
                removalPrompt = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { removalPrompt = nil }
        } message: { prompt in
            Text(verbatim: prompt.message)
        }
        .sheet(item: $operation, onDismiss: {
            guard continueAfterRemoval else { return }
            continueAfterRemoval = false
            generateAndInstall()
        }) { operation in
            LongOperationSheet(operation: operation) {
                continueAfterRemoval = operation.errorMessage == nil
                self.operation = nil
            }
        }
        .domainChangeAlert(viewModel: viewModel)
        .onChange(of: viewModel.bundle == nil) { _, missing in
            if !missing { choosingMethod = true }
        }
        .sheet(isPresented: $choosingMethod) { methodSheet }
        .alert("Could not continue", isPresented: Binding(get: { failure != nil },
                                                          set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(verbatim: failure ?? "")
        }
        .navigationDestination(isPresented: $showInstall) {
            if let bundle = viewModel.bundle {
                InstallFlowView(deployment: viewModel.savedDeployment ?? request.deployment,
                                bundle: bundle)
            }
        }
    }

    private var methodSheet: some View {
        InstallMethodSheet(
            services: allChoices.filter(isSelected).compactMap { ServiceRegistry.service($0) },
            scripts: viewModel.bundle?.artifacts.filter { $0.server != nil } ?? [],
            onDevice: {
                choosingMethod = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showInstall = true }
            },
            onCancel: { choosingMethod = false })
    }

    @ViewBuilder
    private var errorAndConfigSections: some View {
        if let message = viewModel.errorMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        Section {
            Button("Edit full configuration…", systemImage: "slider.horizontal.3") {
                onEditFullConfig()
            }
            .infoNote("Edit full configuration", "Opens the configurator with this server's saved settings — domains, ports, dashboard access.")
        }
    }

    private var continueButton: some View {
        Button {
            advance()
        } label: {
            Text(removedServices.isEmpty ? "Continue" : "Apply changes")
                .font(.headline)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: 420)
        }
        .prominentActionButtonStyle()
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            LabeledContent("Domain") {
                Text(verbatim: request.draft.domain).foregroundStyle(.secondary)
            }
            LabeledContent(request.deployment.topology == .singleHost
                           ? "Server address" : "VPS address") {
                Text(verbatim: request.draft.publicIP).foregroundStyle(.secondary)
            }
        } header: {
            InfoSectionHeader("Reinstall", note: "Re-runs the setup scripts on the server using the saved configuration — same keys and identity. The scripts are idempotent; existing data is kept.")
        }
    }

    private var servicesSection: some View {
        Section {
            Toggle(isOn: binding(for: viewModel.mailEngine)) {
                serviceLabel(viewModel.mailEngine, title: UIL10n.string("Mail"),
                             systemImage: "envelope")
            }

            ForEach(ServiceConfigViewModel.extraServiceChoices, id: \.self) { id in
                Toggle(isOn: binding(for: id)) {
                    serviceLabel(id, title: viewModel.serviceDisplayName(id),
                                 systemImage: viewModel.serviceSystemImage(id))
                }
            }

            Toggle(isOn: vpnMasterBinding) {
                serviceLabel(installedVPNProtocols.isEmpty ? nil : .vpnPanel,
                             title: UIL10n.string("VPN"),
                             systemImage: "network.badge.shield.half.filled")
            }
            if viewModel.vpnEnabled {
                ForEach(ServiceConfigViewModel.allVPNProtocols, id: \.self) { proto in
                    Toggle(isOn: binding(for: proto)) {
                        serviceLabel(proto, title: viewModel.serviceDisplayName(proto),
                                     systemImage: viewModel.serviceSystemImage(proto))
                    }
                    .padding(.leading, 16)
                }
            }
        } header: {
            Text("Services")
        } footer: {
            Text(servicesFooter)
        }
    }

    private func serviceLabel(_ id: ServiceID?, title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
            if let id, installed.contains(id) {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var servicesFooter: String {
        if !removedServices.isEmpty {
            return UIL10n.string("Unchecked services are removed from the server before the setup re-runs. Their data stays on disk.")
        }
        if !addedServices.isEmpty {
            return UIL10n.string("The newly checked services are installed on this run. Everything already on the server is kept, data and all.")
        }
        return UIL10n.string("Check a service to install it on this run. The services already on the server keep their data.")
    }

    // MARK: - Selection

    private func isSelected(_ id: ServiceID) -> Bool {
        switch id {
        case _ where ServiceRegistry.mailEngineIDs.contains(id): return viewModel.mailEnabled
        default:
            if ServiceID.vpnProtocols.contains(id) {
                return viewModel.vpnEnabled && viewModel.vpnProtocols.contains(id)
            }
            return viewModel.extraServices.contains(id)
        }
    }

    private func select(_ id: ServiceID, _ on: Bool) {
        switch id {
        case _ where ServiceRegistry.mailEngineIDs.contains(id):
            viewModel.mailEnabled = on
        default:
            if ServiceID.vpnProtocols.contains(id) {
                if on {
                    viewModel.vpnEnabled = true
                    viewModel.vpnProtocols.insert(id)
                } else {
                    viewModel.vpnProtocols.remove(id)
                    if viewModel.vpnProtocols.isEmpty { viewModel.vpnEnabled = false }
                }
            } else if on {
                viewModel.extraServices.insert(id)
            } else {
                viewModel.extraServices.remove(id)
            }
        }
    }

    private func binding(for id: ServiceID) -> Binding<Bool> {
        Binding(
            get: { isSelected(id) },
            set: { on in
                guard !on, needsRemovalConfirmation(for: id) else {
                    select(id, on)
                    return
                }
                removalPrompt = ServiceRemovalPrompt(message: removalMessage(for: id),
                                                    apply: { select(id, false) })
            }
        )
    }

    /// The master VPN switch
    private var vpnMasterBinding: Binding<Bool> {
        Binding(
            get: { viewModel.vpnEnabled },
            set: { on in
                guard !on, !installedVPNProtocols.isEmpty else {
                    viewModel.vpnEnabled = on
                    return
                }
                removalPrompt = ServiceRemovalPrompt(
                    message: UIL10n.string("The VPN panel and every protocol behind it are stopped and removed. Client configurations and panel accounts stay on disk."),
                    apply: {
                        viewModel.vpnEnabled = false
                        viewModel.vpnProtocols.removeAll()
                    })
            }
        )
    }

    private func displayName(_ id: ServiceID) -> String {
        ServiceRegistry.mailEngineIDs.contains(id)
            ? UIL10n.string("Mail") : viewModel.serviceDisplayName(id)
    }

    private func needsRemovalConfirmation(for id: ServiceID) -> Bool {
        installed.contains(id)
    }

    private func removalMessage(for id: ServiceID) -> String {
        if ServiceID.vpnProtocols.contains(id) {
            return UIL10n.string("The VPN services are removed together and the ones still checked are installed again by this run. Client configurations and panel accounts stay on disk.")
        }
        return UIL10n.string("%@ is stopped and removed from the server. Its data and backups stay on disk.",
                             displayName(id))
    }

    // MARK: - Diff

    private var installedVPNProtocols: Set<ServiceID> {
        installed.intersection(ServiceID.vpnProtocols)
    }

    /// Services checked here but not on the server yet
    private var addedServices: [ServiceID] {
        allChoices.filter { isSelected($0) && !installed.contains($0) }
    }

    /// Installed services this run takes down
    private var removedServices: [ServiceID] {
        var out = allChoices.filter {
            !ServiceID.vpnProtocols.contains($0) && installed.contains($0) && !isSelected($0)
        }
        if installedVPNProtocols.contains(where: { !isSelected($0) }) {
            out.append(.vpnPanel)
        }
        return out
    }

    private var allChoices: [ServiceID] {
        [viewModel.mailEngine] + ServiceConfigViewModel.extraServiceChoices
            + ServiceConfigViewModel.allVPNProtocols
    }

    // MARK: - Run

    private func advance() {
        let removals = removedServices
        guard !removals.isEmpty else {
            generateAndInstall()
            return
        }
        let state = LongOperationState(
            title: UIL10n.string("Removing services"),
            progressText: UIL10n.string("Stopping and removing containers…"))
        operation = state
        OperationActivities.shared.start(id: state.id, title: state.title,
                                         serverName: request.deployment.name,
                                         progressText: state.progressText)
        Task { await runRemovals(removals, into: state) }
    }

    private func generateAndInstall() {
        Task {
            await viewModel.generate()
            if viewModel.bundle != nil {
                choosingMethod = true
            } else if !viewModel.pendingDomainChange, let message = viewModel.errorMessage {
                failure = message
            }
        }
    }

    @MainActor
    private func runRemovals(_ ids: [ServiceID], into state: LongOperationState) async {
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(
                deployment: request.deployment, shared: false)
            for id in ids {
                guard let service = ServiceRegistry.service(id) else { continue }
                state.progressText = UIL10n.string("Removing %@…", service.displayName)
                OperationActivities.shared.update(id: state.id, progressText: state.progressText)
                let ops = ServiceOperations(runner: runner,
                                            deployment: request.deployment,
                                            service: service)
                state.log = try await ops.uninstall(purge: .none) { chunk in
                    Task { @MainActor in
                        state.log = OutputTail.tail(ANSIStripper.strip(state.log + chunk), maxCharacters: OutputTail.logCharacters)
                    }
                }
            }
            state.progressText = UIL10n.string("Removed. Continue to re-run the setup.")
        } catch {
            state.errorMessage = DashboardViewModel.message(for: error)
        }
        state.isFinished = true
        OperationActivities.shared.end(id: state.id, progressText: state.progressText,
                                       errorMessage: state.errorMessage)
    }
}

private struct ServiceRemovalPrompt: Identifiable {
    let id = UUID()
    let message: String
    let apply: () -> Void
}
