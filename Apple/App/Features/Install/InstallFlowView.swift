import SwiftUI
import gryonixNexusCore
import ServerControl
import ServiceCatalog

struct InstallFlowView: View {
    @ObservedObject private var viewModel: InstallViewModel
    private let deployment: Deployment
    private let isSheet: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showDKIM = false

    init(deployment: Deployment, bundle: GeneratedBundle) {
        self.deployment = deployment
        self.isSheet = false
        _viewModel = ObservedObject(
            wrappedValue: InstallSessionRegistry.shared.session(for: deployment, bundle: bundle))
    }

    init(session: InstallViewModel, isSheet: Bool = false) {
        self.deployment = session.deployment
        self.isSheet = isSheet
        _viewModel = ObservedObject(wrappedValue: session)
    }

    var body: some View {
        debugTasks(Form {
            phaseSections
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle("Installation")
        .raisedNavigationTitle()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .wizardBack) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .ownsBottomEdge()
        .sheet(isPresented: $showDKIM) {
            NavigationStack {
                DKIMRecordView(records: viewModel.dkimRecords, onDone: {
                    showDKIM = false
                    openServer()
                })
                #if DEBUG
                .task {
                    if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_DKIM"] != nil {
                        print("DKIM-DEBUG appeared \(Date().timeIntervalSince1970)")
                    }
                }
                #endif
            }
        }
        .task {
            await viewModel.loadIdentityIfNeeded()
        })
    }

    @ViewBuilder
    private var phaseSections: some View {
        switch viewModel.phase {
        case .setup:
            setupSections
        case .installing:
            progressSection
            logSection
        case .finished:
            finishedSections
        case .failed(let message):
            failureSection(message)
            portConflictSection
            dnsFailureSection
            logSection
        }
    }

    @ViewBuilder
    private func debugTasks(_ content: some View) -> some View {
        #if DEBUG
        content
        .task {
            guard InstallResetProbe.autoDrive else { return }
            if InstallResetProbe.stopsAtSetup {
                viewModel.debugSeedHardware()
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            InstallResetProbe.note("auto-drive: InstallFlowView on screen, forcing installing")
            viewModel.debugForceInstalling()
        }
        .task {
            guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_INSTALL_DONE"] != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            viewModel.debugSeedFinished()
        }
        .task {
            guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_DKIM"] != nil else { return }
            viewModel.debugSeedFinished()
            try? await Task.sleep(for: .seconds(2))
            print("DKIM-DEBUG pushing \(Date().timeIntervalSince1970)")
            showDKIM = true
        }
        #else
        content
        #endif
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 6) {
            phaseAction
            #if os(macOS)
            if isSheet {
                Button {
                    dismiss()
                } label: {
                    bottomLabel(Text("Close"))
                }
                .secondaryActionButtonStyle()
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            #endif
        }
    }

    @ViewBuilder
    private var phaseAction: some View {
        switch viewModel.phase {
        case .setup:
            Button {
                viewModel.startInstall()
            } label: {
                bottomLabel(Text("Start Installation"))
            }
            .prominentActionButtonStyle()
            .controlSize(.large)
            .disabled(!viewModel.canStart)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        case .finished:
            if viewModel.mailWasInstalled {
                Button {
                    showDKIM = true
                } label: {
                    bottomLabel(Text("Next — DKIM record"))
                }
                .prominentActionButtonStyle()
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            } else {
                Button(action: openServer) {
                    bottomLabel(Text("Open server"))
                }
                .prominentActionButtonStyle()
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        case .installing, .failed:
            EmptyView()
        }
    }

    private func bottomLabel(_ text: Text) -> some View {
        text
            .font(.headline)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: 420)
    }

    private func openServer() {
        AppNavigator.shared.openServer(deployment.id)
    }

    // MARK: - Setup phase

    @ViewBuilder
    private var setupSections: some View {
        accessGrantSections

        ForEach($viewModel.targets) { $target in
            Section {
                TechnicalField(title: "Address", prompt: addressPrompt(target.kind), text: $target.address,
                               ownAddress: true)
                    .onChange(of: target.address) {
                        viewModel.addressChanged(target.id)
                    }
                TechnicalField(title: "Install user", prompt: "root", text: $target.username)
                    .onChange(of: target.username) {
                        viewModel.addressChanged(target.id)
                    }
                HStack {
                    Button("Check connection") {
                        viewModel.checkConnection(target.id)
                    }
                    .rowActionButtonStyle()
                    .disabled(target.address.trimmingCharacters(in: .whitespaces).isEmpty
                              || target.connection == .checking)
                    Spacer()
                    connectionStatus(target.connection)
                }
                if case .failed(let message) = target.connection {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if case .needsSudoPassword(let error) = target.connection {
                    SudoPasswordPrompt(username: target.username, error: error, isWorking: false) {
                        viewModel.grantSudo(target.id, password: $0)
                    }
                }
                SwapRow(target: target) { viewModel.addSwap(target.id, sizeGB: $0) }
            } header: {
                Text(title(for: target.kind))
            } footer: {
                if target.kind == .home {
                    Text("Address of the local server on your network (the app must be on the same network). It is used only during installation — afterwards the dashboard reaches this machine through the WireGuard tunnel.")
                }
            }

            SSHSecretSection(
                draft: $target.secret,
                appKeyIsInstalled: true,
                appKeyFooter: "Uses the key granted in step 1 above. Nothing new is stored on this device."
            )
            .onChange(of: target.secret.kind) {
                viewModel.credentialChanged(target.id)
            }

            ServerHardwareSections(target: $target, requirements: viewModel.requirements(for: target.kind),
                                   isRelay: target.kind == .vps)
        }
    }

    @ViewBuilder
    private var accessGrantSections: some View {
        if viewModel.needsAccessGrant {
        Section {
            if viewModel.publicKey != nil {
                HStack {
                    Button {
                        copyToClipboard(viewModel.grantCommand)
                    } label: {
                        Label("Copy command", systemImage: "terminal")
                    }
                    .rowActionButtonStyle(inline: true)
                }
            } else {
                Label("Could not load the app's SSH key from the Keychain", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Step 1 — grant access")
        } footer: {
            Text("Run the copied command on each server below — in the provider's console or an existing SSH session, signed in as the install user for that server (putting sudo in front is fine). It adds the app's public key to that account's authorized_keys and prints the account it authorized: that name must match the install user below. The access is temporary — the script removes the key again at the end of the installation, leaving only the restricted control user. Machines you sign in to with a password need none of this.")
        }

        if let key = viewModel.publicKey {
            AdvancedSection {
                HStack(alignment: .firstTextBaseline) {
                    Text(key)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Spacer(minLength: 12)
                    Button {
                        copyToClipboard(key)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .rowActionButtonStyle(inline: true)
                }
            }
        }
        }
    }

    @ViewBuilder
    private func dnsRecordsRows(_ records: String) -> some View {
        Text(records)
            .font(.caption.monospaced())
            .textSelection(.enabled)
        Button {
            copyToClipboard(records)
        } label: {
            Label("Copy records", systemImage: "doc.on.doc")
        }
        .rowActionButtonStyle(inline: true)
    }

    private func addressPrompt(_ kind: InstallViewModel.Target.Kind) -> String {
        kind == .home ? "192.168.1.20" : "203.0.113.10"
    }

    private func title(for kind: InstallViewModel.Target.Kind) -> LocalizedStringKey {
        switch kind {
        case .single: return "Server"
        case .vps: return "VPS (entry point)"
        case .home: return "Local server"
        }
    }

    @ViewBuilder
    private func connectionStatus(_ state: InstallViewModel.ConnectionState) -> some View {
        switch state {
        case .unchecked:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .checking:
            ProgressView().controlSize(.small)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsSudoPassword:
            Image(systemName: "key.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    // MARK: - Installing phase

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title(for: currentKind))
                        .font(.headline)
                    Spacer()
                    if viewModel.stepTotal > 0 {
                        Text(verbatim: "\(Int((viewModel.overallProgress * 100).rounded()))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: viewModel.overallProgress)
                Text(viewModel.stage.isEmpty ? UIL10n.string("Connecting…") : viewModel.stage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 4)
            Button("Cancel", role: .destructive) {
                viewModel.cancel()
            }
            .rowActionButtonStyle()
            .dangerTint()
        } header: {
            Text("Installing")
        } footer: {
            Text("You can minimise the app: the installation keeps running on the server, and the app picks it up when you come back.")
        }
    }

    private var currentKind: InstallViewModel.Target.Kind {
        let index = min(viewModel.currentTargetIndex, viewModel.targets.count - 1)
        return viewModel.targets.indices.contains(index) ? viewModel.targets[index].kind : .single
    }

    private func outputBox(_ lines: [String], anchorID: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id(anchorID)
                }
            }
            .frame(height: Self.outputBoxHeight)
            .onChange(of: lines.count) {
                proxy.scrollTo(anchorID, anchor: .bottom)
            }
            .onChange(of: lines.last) {
                proxy.scrollTo(anchorID, anchor: .bottom)
            }
        }
    }

    private static let outputBoxHeight: CGFloat = 220

    @ViewBuilder
    private var logSection: some View {
        if !viewModel.logLines.isEmpty {
            Section("Log") {
                outputBox(viewModel.logLines, anchorID: "log-end")
            }
        }
    }

    // MARK: - Finished / failed

    @ViewBuilder
    private var finishedSections: some View {
        Section {
            Label("Installation complete", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.headline)
        } footer: {
            Text("The server is already in the Servers tab — the app now connects as the restricted control user; its temporary root access has been revoked by the script.")
        }
        if !viewModel.installWarnings.isEmpty {
            Section {
                ForEach(viewModel.installWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            } header: {
                Text("Needs attention")
            } footer: {
                Text("The rest of the install finished — these are non-fatal steps that did not, and can be fixed by re-running setup afterward.")
            }
        }
        ForEach(viewModel.reports) { report in
            Section {
                Text(report.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button {
                    copyToClipboard(report.text)
                } label: {
                    Label("Copy report", systemImage: "doc.on.doc")
                }
                .rowActionButtonStyle(inline: true)
            } header: {
                Text("Report") + Text(verbatim: " — ") + Text(title(for: report.targetKind))
            } footer: {
                Text("The report is also saved on this device (Keychain) — reopen it any time via “Login & Passwords” in the dashboard.")
            }
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            Label("The installation stopped", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            outputBox(message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                      anchorID: "failure-end")
            Button {
                viewModel.retry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .rowActionButtonStyle()
        } header: {
            Text("Installation failed")
        } footer: {
            if viewModel.sawPortConflict {
                Text("Nothing was installed on that machine — the run stopped before it created anything.")
            } else {
                Text("The scripts are idempotent: retrying re-runs the failed machine from the top and skips what is already done. Machines that finished are not re-run.")
            }
        }
    }

    @ViewBuilder
    private var portConflictSection: some View {
        if viewModel.sawPortConflict {
            Section {
                Label("A port is already in use", systemImage: "network.slash")
                    .foregroundStyle(.orange)
            } footer: {
                Text("Another service on that machine already answers on a port this installation needs — the output above names it. Two DNS filters, or two mail servers, cannot share one machine. Remove the service that holds the port (or install this one on another machine), then tap Retry.")
            }
        }
    }

    @ViewBuilder
    private var dnsFailureSection: some View {
        if viewModel.sawDNSCheckFailure, let records = viewModel.dnsRecordsText {
            Section {
                Label("DNS records are missing", systemImage: "globe")
                    .foregroundStyle(.orange)
                Button {
                    viewModel.retry(skipDNSCheck: true)
                } label: {
                    Label("Retry without the DNS check", systemImage: "arrow.clockwise")
                }
                .rowActionButtonStyle()
                dnsRecordsRows(records)
            } footer: {
                Text("The domain does not point to this server yet. Add these records at your DNS provider, wait for DNS to update (it can take a few minutes), then tap Retry. If you have already added them, skipping the check runs the setup anyway — but TLS certificates only get issued once the records really resolve.")
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        guard LicensePrompt.shared.allow() else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}
