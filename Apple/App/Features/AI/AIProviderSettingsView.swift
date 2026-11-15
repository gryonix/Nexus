import AIAssistant
import ServerControl
import ServiceCatalog
import SwiftUI

struct AIProviderSettingsView: View {
    @ObservedObject private var settings = AISettings.shared
    @State private var key = ""
    @State private var pendingProvider: String?
    @State private var servers: [Deployment] = []
    @State private var installed: [String] = []

    var body: some View {
        CardList {
            providerSection
            if settings.isOnDevice {
                AIOnDeviceSection()
            } else if settings.isOllama {
                ollamaSection
            } else if !settings.providerID.isEmpty {
                cloudSection
            }
            limitSection
        }
        .screenTitle("AI provider")
        .task { servers = ((try? FileDeploymentStore().load()) ?? []).filter { $0.services.contains(.ollama) } }
        .task(id: settings.ollamaServerID) { await loadInstalled() }
        .sheet(item: Binding(get: { pendingProvider.map(Pending.init) }, set: { _ in pendingProvider = nil })) { item in
            notice(for: item.id)
        }
    }

    private struct Pending: Identifiable { let id: String }

    private var providerSection: some View {
        Section {
            Picker("Provider", selection: Binding(get: { settings.providerID }, set: choose)) {
                Text("None").tag("")
                ForEach(LLMProvider.all) { Text(verbatim: $0.displayName).tag($0.id) }
                Text("Ollama on my server").tag(AIProviderConfig.ollamaID)
                if AIOnDevice.status != .needsNewerSystem {
                    Text("On this device (Apple)").tag(AIProviderConfig.onDeviceID)
                }
            }
        } footer: {
            Text("The AI only explains and suggests. It never runs anything on your servers.")
        }
    }

    private func choose(_ id: String) {
        guard id != settings.providerID else { return }
        settings.providerID = id
        settings.model = AIProviderConfig.suggestedModel(id)
        key = settings.apiKey(for: id)
        let seen = id == AIProviderConfig.ollamaID ? settings.hasSeenLocalNotice : settings.hasSeenCloudNotice(id)
        if !id.isEmpty, id != AIProviderConfig.onDeviceID, !seen { pendingProvider = id }
    }

    @ViewBuilder
    private func notice(for id: String) -> some View {
        if id == AIProviderConfig.ollamaID {
            AILocalNoticeSheet(onAgree: { settings.markLocalNoticeSeen(); pendingProvider = nil },
                               onCancel: { pendingProvider = nil })
        } else {
            AICloudNoticeSheet(providerName: LLMProvider.provider(id: id)?.displayName ?? id,
                               onAgree: { settings.markCloudNoticeSeen(id); pendingProvider = nil },
                               onCancel: { settings.providerID = ""; pendingProvider = nil })
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        let provider = LLMProvider.provider(id: settings.providerID)
        Section {
            TechnicalField(title: "Model", prompt: AIProviderConfig.suggestedModel(settings.providerID),
                           text: $settings.model)
            SecureTechnicalField(title: "API key", text: Binding(
                get: { key.isEmpty ? settings.apiKey(for: settings.providerID) : key },
                set: { key = $0; settings.setAPIKey($0, for: settings.providerID) }))
            if let provider {
                Text(verbatim: provider.consoleURL).font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            Text("The key stays on this device and is not synced.")
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        Section {
            Picker("Server", selection: $settings.ollamaServerID) {
                Text("Address below").tag("")
                ForEach(servers) { Text(verbatim: $0.name).tag($0.id.uuidString) }
            }
            if settings.ollamaServerID.isEmpty {
                TechnicalField(title: "Ollama address", prompt: "https://ollama.example.net", text: $settings.ollamaURL)
            }
            TechnicalField(title: "Model", prompt: "llama3.2:3b", text: $settings.model)
            if !installed.isEmpty {
                Picker("Installed models", selection: $settings.model) {
                    ForEach(installed, id: \.self) { Text(verbatim: $0).tag($0) }
                }
            }
        } footer: {
            Text("Your data stays at home")
        }
    }

    private var limitSection: some View {
        Section {
            if !settings.isLocal {
                Stepper(value: $settings.monthlyLimit, in: 0...50_000_000, step: 50_000) {
                    Text("Monthly token limit: \(settings.monthlyLimit == 0 ? "–" : String(settings.monthlyLimit))")
                }
                Text("Used this month: \(settings.usedThisMonth)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            if !settings.isLocal { Text("0 means no limit. Counts stay on this device.") }
        }
    }

    private func loadInstalled() async {
        guard let id = UUID(uuidString: settings.ollamaServerID),
              let deployment = servers.first(where: { $0.id == id }) else { installed = []; return }
        if #available(macOS 15.0, *) {
            let listing = await LocalModels.list(deployment: deployment)
            installed = listing.models.map(\.name)
        }
    }
}
