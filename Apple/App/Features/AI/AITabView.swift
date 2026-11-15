import AIAssistant
import ServiceCatalog
import SwiftUI

/// The AI section: chats, weekly summary and provider settings.
struct AITabView: View {
    @ObservedObject private var store = AIChatStore.shared
    @ObservedObject private var settings = AISettings.shared
    @ObservedObject private var modules = ModuleSettings.shared
    @State private var path: [String] = []
    @State private var summarising = false

    var body: some View {
        if settings.agreed { chats } else { agreement }
    }

    private var chats: some View {
        NavigationStack(path: $path) {
            list
                .screenTitle("AI")
                .sectionToolbar(.ai)
                .navigationDestination(for: String.self) { AIChatView(chatID: $0) }
                .onChange(of: store.openChatID, initial: true) { _, id in
                    if let id { path = [id]; store.openChatID = nil }
                }
                #if DEBUG
                .task { openDemoChat() }
                #endif
        }
    }

    private var agreement: some View {
        AIModuleAgreementSheet(onAgree: { settings.agreed = true },
                               onCancel: { modules.set(.ai, on: false) })
    }

    private var list: some View {
        CardList {
            Section {
                NavigationLink { AIProviderSettingsView() } label: {
                    if settings.isConfigured {
                        Label(title: { Text(verbatim: "\(settings.providerID) · \(settings.model)") },
                              icon: { Image(systemName: "slider.horizontal.3") })
                    } else {
                        Label("Choose a provider", systemImage: "slider.horizontal.3")
                    }
                }
                Button { Task { await weekly() } } label: {
                    if summarising { ProgressView() } else { Label("Weekly summary", systemImage: "calendar") }
                }
                .disabled(summarising)
                Button { path = [store.newChat(title: UIL10n.string("New chat"))] } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
            }
            ForEach(store.history.groups(now: Date()), id: \.0) { group, chats in
                Section(title(group)) {
                    ForEach(chats) { chat in
                        NavigationLink(value: chat.id) { Text(verbatim: chat.title).lineLimit(1) }
                    }
                    .onDelete { offsets in offsets.forEach { store.delete(chats[$0].id) } }
                }
            }
        }
    }

    #if DEBUG
    /// Opens the newest chat, or a new one, for screenshots
    private func openDemoChat() {
        guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_AI_CHAT"] != nil else { return }
        path = [store.history.chats.first?.id ?? store.newChat(title: UIL10n.string("New chat"))]
    }
    #endif

    private func weekly() async {
        summarising = true
        defer { summarising = false }
        store.start(await AIWeeklySummary.context())
    }

    private func title(_ group: AIDateGroup) -> LocalizedStringKey {
        switch group {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .lastWeek: return "Previous 7 days"
        case .earlier: return "Earlier"
        }
    }
}
