import AgentClient
import SwiftUI

/// App-wide push notification settings
struct NotificationSettingsView: View {
    @AppStorage(NotifyPreferences.Key.disks) private var disks = true
    @AppStorage(NotifyPreferences.Key.spacePercent) private var spacePercent = 90
    @AppStorage(NotifyPreferences.Key.services) private var services = true
    @AppStorage(NotifyPreferences.Key.backups) private var backups = true
    @AppStorage(NotifyPreferences.Key.agentUpdate) private var agentUpdate = true
    @AppStorage(NotifyPreferences.Key.appUpdate) private var appUpdate = true
    @AppStorage(NotifyPreferences.Key.operations) private var operations = false
    @AppStorage(NotifyPreferences.Key.sshLogins) private var sshLogins = true
    @AppStorage(NotifyPreferences.Key.unusualLoad) private var unusualLoad = true
    @AppStorage(NotifyPreferences.Key.widgetMinutes) private var widgetMinutes = 60

    @ObservedObject private var push = PushRegistration.shared
    @State private var channel = NotifyChannelDefault.current()
    @State private var channelChanged = false
    @State private var holding: Int?
    @State private var confirmingStop = false
    @State private var stopped: Int?

    var body: some View {
        Form {
            channelSection
            eventsSection
            NotifySoundsSection { channelChanged = true }
            widgetsSection
            thisDeviceSection
        }
        .screenTitle("Push notifications")
        .onChange(of: channel) { _, chosen in
            chosen.save()
            channelChanged = true
        }
        .onChange(of: channel.channel) { _, picked in
            if picked == .relay { Task { _ = await push.requestToken() } }
        }
        .onDisappear {
            guard channelChanged else { return }
            channelChanged = false
            NotifyFleetSync.shared.syncAll()
        }
    }

    private var channelSection: some View {
        Section {
            WrappingPicker("Send through", selection: $channel.channel) {
                Text("Nothing").tag(Gryonixnexusd_V1_NotifyChannel.off)
                Text(verbatim: "gryonixPush").tag(Gryonixnexusd_V1_NotifyChannel.relay)
                Text(verbatim: "ntfy").tag(Gryonixnexusd_V1_NotifyChannel.ntfy)
            }
            switch channel.channel {
            case .relay: NotifyRelayFields(url: $channel.relayURL)
            case .ntfy: NotifyNtfyFields(url: $channel.ntfyURL, topic: $channel.ntfyTopic)
            default: EmptyView()
            }
        } header: {
            InfoSectionHeader("Where notifications go", note: "The default for every server. Each server picks it up the next time the app connects to it, and with gryonixPush this device signs up for its alerts by itself. A server can keep its own choice under Agent → Notifications.")
        }
    }

    private var widgetsSection: some View {
        Section {
            WrappingPicker("Update widgets", selection: $widgetMinutes) {
                ForEach(NotifyPreferences.widgetMinuteChoices, id: \.self) { minutes in
                    Text(verbatim: Self.spelled(minutes: minutes)).tag(minutes)
                }
            }
        } header: {
            InfoSectionHeader("Widgets", note: "How often each server sends fresh readings to the widgets on this device. It needs gryonixPush, and the system may deliver them less often to save battery.")
        }
        .onChange(of: widgetMinutes) { channelChanged = true }
    }

    /// A span of minutes in the reader's language
    static func spelled(minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private var eventsSection: some View {
        Section {
            NotifyEventToggles(disks: $disks, spacePercent: $spacePercent, services: $services,
                               backups: $backups, agentUpdate: $agentUpdate, operations: $operations,
                               sshLogins: $sshLogins, unusualLoad: $unusualLoad)
            Toggle("A new app version", isOn: $appUpdate)
        } header: {
            InfoSectionHeader("Notify me about", note: "These are the defaults for every server, and each server picks them up the next time the app connects to it. A server can keep its own choice under Agent → Notifications.")
        }
    }

    @ViewBuilder private var thisDeviceSection: some View {
        if let token = push.token {
            Section {
                if let holding {
                    LabeledContent("Servers notifying this device") { Text(verbatim: "\(holding)") }
                }
                Button("Stop every server notifying this device", role: .destructive) { confirmingStop = true }
                    .dangerTint()
                if let stopped {
                    Text("Removed from \(stopped) server(s). Turn notifications on again from a server's Notifications to get them back.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                InfoSectionHeader("This device", note: "Asks the relay to forget this device for every server at once, whoever runs them. It does not need the servers to answer.")
            }
            .task { holding = await PushRelays.serversHolding(token: token) }
            .confirmationDialog("Stop every server notifying this device?", isPresented: $confirmingStop,
                                titleVisibility: .visible) {
                Button("Stop them all", role: .destructive) {
                    Task {
                        stopped = await PushRelays.stopAll(token: token)
                        holding = await PushRelays.serversHolding(token: token)
                    }
                }
                .dangerTint()
            }
        }
    }
}

/// A sound for each kind of alert
private struct NotifySoundsSection: View {
    let onChange: () -> Void

    var body: some View {
        Section {
            ForEach(NotifySoundGroup.allCases) { group in
                NotifySoundPicker(group: group, onChange: onChange)
            }
        } header: {
            InfoSectionHeader("Sounds", note: "Each kind of alert can play its own sound on this device. Default is the system's notification sound.")
        }
    }
}

private struct NotifySoundPicker: View {
    let group: NotifySoundGroup
    let onChange: () -> Void
    @AppStorage private var raw: String

    init(group: NotifySoundGroup, onChange: @escaping () -> Void) {
        self.group = group
        self.onChange = onChange
        _raw = AppStorage(wrappedValue: NotifySound.standard.rawValue, NotifySounds.key(group))
    }

    var body: some View {
        WrappingPicker(group.title, selection: Binding(
            get: { NotifySound(rawValue: raw) ?? .standard },
            set: { picked in
                raw = picked.rawValue
                picked.play()
                onChange()
            })) {
            ForEach(NotifySound.allCases) { sound in
                Text(sound.title).tag(sound)
            }
        }
    }
}
