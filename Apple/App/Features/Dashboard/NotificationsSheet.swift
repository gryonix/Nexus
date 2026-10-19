import AgentClient
import AgentControl
import SwiftUI
import UniformTypeIdentifiers

/// Where this server's health alerts go and what it checks
@available(macOS 15.0, *)
struct NotificationsSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var push = PushRegistration.shared
    @Environment(\.dismiss) private var dismiss
    @State private var settings: Gryonixnexusd_V1_NotifySettings?
    @State private var draft = Gryonixnexusd_V1_SetNotifySettingsRequest()
    @State private var isWorking = false
    @State private var message: QuickActionResult?
    @State private var exporting: NotifyTransferDocument?
    @State private var isImporting = false
    /// The server follows Settings → Push notifications
    @State private var followsApp = false

    var body: some View {
        NavigationStack {
            CardList {
                channelSection
                eventsSection
                NotifyStatusSection(settings: settings)
                actionsSection
                transferSection
            }
            .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                          document: exporting, contentType: .json,
                          defaultFilename: "gryonixPush-\(viewModel.deployment.name)") { result in
                if case .failure(let error) = result {
                    message = QuickActionResult(message: error.localizedDescription, isError: true)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                importFile(result)
            }
            .navigationTitle(Text("Notifications"))
            .raisedNavigationTitle()
            .disabled(isWorking)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { run { try await save() } }.disabled(!canSave)
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder private var channelSection: some View {
        Section {
            Toggle("Use the app's choice", isOn: followsAppBinding)
            WrappingPicker("Send through", selection: $draft.channel) {
                Text("Nothing").tag(Gryonixnexusd_V1_NotifyChannel.off)
                Text(verbatim: "gryonixPush").tag(Gryonixnexusd_V1_NotifyChannel.relay)
                Text(verbatim: "ntfy").tag(Gryonixnexusd_V1_NotifyChannel.ntfy)
            }
            .disabled(followsApp)
            if !followsApp {
                switch draft.channel {
                case .relay: NotifyRelayFields(url: $draft.relayURL)
                case .ntfy: NotifyNtfyFields(url: $draft.ntfyURL, topic: $draft.ntfyTopic)
                default: EmptyView()
                }
            }
        } header: {
            InfoSectionHeader("Channel") {
                Text("The server checks itself every quarter of an hour and tells you when something breaks or recovers, even while this app is closed.")
                Text("gryonixPush sends real notifications to this app. ntfy needs the free ntfy app and no account.")
            }
        }
    }

    @ViewBuilder private var eventsSection: some View {
        Section {
            Toggle("Use the app's default settings", isOn: followsDefaults)
            if draft.customChecks {
                NotifyEventToggles(checks: $draft.checks)
            }
        } header: {
            InfoSectionHeader("Notify me about", note: "With the app's defaults, this server follows Settings → Notifications and keeps following it. Turn them off to choose for this server alone.")
        }
    }

    private var followsAppBinding: Binding<Bool> {
        Binding(get: { followsApp }, set: { follow in
            followsApp = follow
            if follow { draft = NotifyChannelDefault.current().applied(to: draft) }
        })
    }

    private var followsDefaults: Binding<Bool> {
        Binding(get: { !draft.customChecks }, set: { follow in
            draft.customChecks = !follow
            if follow { draft.checks = NotifyPreferences.current().checks }
        })
    }

    @ViewBuilder private var actionsSection: some View {
        Section {
            if settings?.channel == .relay {
                Button("Get notifications on this device") { run { try await registerThisDevice() } }
                if let failure = push.failure {
                    Text(verbatim: failure).font(.footnote).foregroundStyle(.orange)
                }
            }
            Button("Send a test notification") { run { try await sendTest() } }
                .disabled(settings?.channel == .off || settings == nil)
            if let message {
                Text(verbatim: message.message).font(.footnote)
                    .foregroundStyle(message.isError ? .red : .secondary)
            }
        }
    }

    @ViewBuilder private var transferSection: some View {
        Section {
            Button("Export these settings…") {
                if let data = try? NotifyTransfer(request: draft).encoded() {
                    exporting = NotifyTransferDocument(data: data)
                }
            }
            Button("Import settings…") { isImporting = true }
        } footer: {
            Text("The file holds the channel, its address and topic, and the choices above. Anyone who has an ntfy topic can read the alerts, so keep the file private. Nothing is sent until you tap Save.")
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            draft = try NotifyTransfer.decode(Data(contentsOf: url)).applied(to: draft)
            if !draft.customChecks { draft.checks = NotifyPreferences.current().checks }
            message = QuickActionResult(message: UIL10n.string("Settings loaded. Tap Save to use them."), isError: false)
        } catch NotifyTransfer.Failure.newerVersion {
            message = QuickActionResult(message: UIL10n.string("This file comes from a newer version of the app."), isError: true)
        } catch {
            message = QuickActionResult(message: UIL10n.string("This is not a gryonixPush settings file."), isError: true)
        }
    }

    private var canSave: Bool {
        switch draft.channel {
        case .relay: return draft.relayURL.hasPrefix("https://") || draft.relayURL.hasPrefix("http://")
        case .ntfy: return !draft.ntfyTopic.isEmpty && !draft.ntfyURL.isEmpty
        case .off: return true
        default: return false
        }
    }

    private func operations() async throws -> AgentNotifyOperations {
        try await viewModel.notifyOperations()
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            do { try await work() } catch {
                message = QuickActionResult(message: DashboardViewModel.message(for: error), isError: true)
            }
            isWorking = false
        }
    }

    private func load() async {
        do {
            let current = try await operations().settings()
            settings = current
            followsApp = !NotifyChannelDefault.keepsOwn(current, deploymentID: viewModel.deployment.id,
                                                        wanted: NotifyChannelDefault.current())
            draft = NotifyDraft.request(from: current)
        } catch {
            message = QuickActionResult(message: DashboardViewModel.message(for: error), isError: true)
        }
    }

    private func save() async throws {
        if followsApp { draft = NotifyChannelDefault.current().applied(to: draft) }
        UserDefaults.standard.set(!followsApp, forKey: NotifyChannelDefault.ownKey(for: viewModel.deployment.id))
        draft.language = ContentLanguageSetting.current.rawValue
        if !draft.customChecks { draft.checks = NotifyPreferences.current().checks }
        draft.appPublicKey = await DashboardViewModel.devicePublicKey(for: viewModel.deployment)
        let saved = try await operations().save(draft)
        settings = saved
        await viewModel.mirrorNotify(saved)
        UserDefaults.standard.removeObject(forKey: DashboardViewModel.notifySyncedKey(for: viewModel.deployment.id))
        message = saved.lastError.isEmpty
            ? QuickActionResult(message: UIL10n.string("Saved."), isError: false)
            : QuickActionResult(message: saved.lastError, isError: true)
    }

    private func registerThisDevice() async throws {
        guard let token = await push.requestToken() else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        settings = try await operations().register(platform: push.platform, token: token, appVersion: version,
                                                   locale: ContentLanguageSetting.current.rawValue,
                                                   muted: NotifyPreferences.current().muted,
                                                   proof: DevicePushProof.proof)
        if let settings {
            PushRelays.remember(settings.relayURL)
            await viewModel.mirrorNotify(settings)
        }
        message = QuickActionResult(message: UIL10n.string("This device now gets this server's alerts."), isError: false)
    }

    private func sendTest() async throws {
        let result = try await operations().test()
        message = QuickActionResult(message: result.ok ? UIL10n.string("Test sent.") : result.message, isError: !result.ok)
        settings = try? await operations().settings()
    }
}

enum NotifyDraft {
    static let defaultRelayURL = "https://push.gryonix.com"

    static func request(from settings: Gryonixnexusd_V1_NotifySettings) -> Gryonixnexusd_V1_SetNotifySettingsRequest {
        var request = Gryonixnexusd_V1_SetNotifySettingsRequest()
        request.channel = settings.channel == .unspecified ? .off : settings.channel
        request.relayURL = settings.relayURL.isEmpty ? defaultRelayURL : settings.relayURL
        request.ntfyURL = settings.ntfyURL.isEmpty ? "https://ntfy.sh" : settings.ntfyURL
        request.ntfyTopic = settings.ntfyTopic
        request.checks = settings.checks
        request.language = settings.language
        request.customChecks = settings.customChecks
        return request
    }

    /// A topic nobody guesses
    static func randomTopic() -> String {
        "gnx-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
    }
}

struct NotifyRelayFields: View {
    @Binding var url: String

    var body: some View {
        TextField("Relay address", text: $url, prompt: Text(verbatim: "https://push.example.com"))
            .textContentType(.URL)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }
}

struct NotifyNtfyFields: View {
    @Binding var url: String
    @Binding var topic: String

    var body: some View {
        TextField("ntfy server", text: $url, prompt: Text(verbatim: "https://ntfy.sh"))
            .textContentType(.URL)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        HStack {
            TextField("Topic", text: $topic)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("New") { topic = NotifyDraft.randomTopic() }
                .buttonStyle(.borderless)
        }
        .onAppear { if topic.isEmpty { topic = NotifyDraft.randomTopic() } }
        Text("Subscribe to this topic in the ntfy app. Anyone who knows the topic can read it, so keep it random.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

struct NotifyStatusSection: View {
    let settings: Gryonixnexusd_V1_NotifySettings?

    var body: some View {
        if let settings {
            Section {
                if settings.lastCheckAt > 0 {
                    LabeledContent("Last check") {
                        Text(Date(timeIntervalSince1970: TimeInterval(settings.lastCheckAt)), style: .relative)
                    }
                }
                if settings.channel == .relay {
                    LabeledContent("Devices", value: "\(settings.devices)")
                }
                ForEach(settings.activeProblems, id: \.self) { problem in
                    Label { Text(verbatim: problem) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                if !settings.relayMaintenance.isEmpty {
                    Text(verbatim: UIL10n.string("The relay is under maintenance: %@", settings.relayMaintenance))
                        .foregroundStyle(.orange)
                }
                if !settings.lastError.isEmpty {
                    Text(verbatim: settings.lastError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Status")
            }
        }
    }
}
