import AgentControl
import gryonixNexusCore
import ServerControl
import ServiceCatalog
import SwiftUI

/// Second step of adding services: their own settings, then install
struct AddServiceSetupStep: View {
    let services: [any ManagedService]
    let deployment: Deployment
    let findings: [InstallFinding]
    let onInstall: (ServiceSettings) -> Void

    @StateObject private var config: ServiceConfigViewModel
    @State private var questions: [ServiceQuestion] = []
    @State private var scripts: [Artifact] = []
    @State private var asking: LicenseGate.Reason?

    init(services: [any ManagedService], deployment: Deployment, findings: [InstallFinding] = [],
         onInstall: @escaping (ServiceSettings) -> Void) {
        self.services = services
        self.deployment = deployment
        self.findings = findings
        self.onInstall = onInstall
        _config = StateObject(wrappedValue: ServiceConfigViewModel(
            topology: deployment.topology,
            restoringConfig: ConfiguratorDraft(recovering: deployment),
            existingServer: deployment))
    }

    private var ids: Set<ServiceID> { Set(services.map(\.id)) }

    private var withFields: [ServiceID] {
        services.map(\.id).filter(ServiceAdvancedFields.hasFields(for:))
    }

    private var unanswered: Bool { questions.contains { !config.isAnswered($0) } }

    private var blockedByMachine: Bool { !HostCompatibilitySection.blocked(findings).isDisjoint(with: ids) }

    var body: some View {
        Form {
            HostCompatibilitySection(findings: findings)
            questionsSection
            ForEach(withFields, id: \.self) { id in
                Section {
                    ServiceAdvancedFields(viewModel: config, id: id)
                } header: {
                    Label(config.serviceDisplayName(id), systemImage: config.serviceSystemImage(id))
                }
            }
            if withFields.isEmpty && questions.isEmpty {
                Section {
                    Text("These services need nothing more from you. Server-wide settings stay as they are.")
                        .foregroundStyle(.secondary)
                }
            }
            installSection
            scriptsSection
        }
        .formStyle(.grouped)
        .screenTitle("Settings")
        .licenseAsk($asking)
        .task { prepare() }
    }

    @ViewBuilder private var questionsSection: some View {
        if !questions.isEmpty {
            Section {
                ForEach(questions) { question in
                    Toggle(question.title, isOn: config.questionBinding(question))
                    if !config.isAnswered(question) {
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

    private var installSection: some View {
        Section {
            Button(action: install) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Install from this device").font(.headline)
                        Text("The agent installs on the server and keeps going if you close the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bolt.fill").foregroundStyle(.tint)
                }
            }
            .disabled(unanswered || blockedByMachine)
            .accessibilityIdentifier("addService.install")
        } header: {
            Text(verbatim: services.map(\.displayName).joined(separator: ", "))
        }
    }

    @ViewBuilder private var scriptsSection: some View {
        if !scripts.isEmpty {
            Section {
                ForEach(scripts) { artifact in
                    NavigationLink {
                        ArtifactDetailView(artifact: artifact)
                    } label: {
                        SimpleArtifactRow(artifact: artifact)
                    }
                }
            } header: {
                Text("Or run the scripts yourself")
            } footer: {
                Text("Or run the script yourself on the server — open it to copy or share the file.")
            }
        }
    }

    /// Asks only what this server has not answered yet
    private func prepare() {
        guard questions.isEmpty, scripts.isEmpty else { return }
        questions = ServiceQuestions.raised(by: ids, topology: deployment.topology, scope: deployment.scope)
            .filter { !config.isAnswered($0) }
        scripts = AddedServiceScripts.scripts(for: services, on: deployment)
    }

    private var editedSettings: ServiceSettings {
        deployment.serviceSettings.adopting(config.makeServiceSettings(), for: ids)
    }

    private func install() {
        guard LicenseStore.shared.status.isActive || DemoFleet.covers(deployment) else {
            asking = LicenseGate.reason
            return
        }
        onInstall(editedSettings)
    }
}
