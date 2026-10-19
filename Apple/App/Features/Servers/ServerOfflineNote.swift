import ServerControl
import SwiftUI

/// What a card shows while its machine does not answer
struct ServerOfflineNote: View {
    let deployment: Deployment
    let host: SSHHostID
    let lastSeen: Date?
    var offlineSince: Date?
    var compact = false

    @State private var waking = false
    @State private var wakeMessage: String?
    @State private var onNetwork: Bool?
    @AppStorage(WakeButtonSettings.delayKey) private var wakeDelay = WakeButtonSettings.defaultDelay
    @ObservedObject private var network = NetworkWatch.shared

    private var canWake: Bool {
        WakeOnLANAvailability.target(in: deployment)?.sshHost == host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Label("No connection", systemImage: "wifi.exclamationmark")
                .font((compact ? Font.caption : .subheadline).weight(.semibold))
                .foregroundStyle(.red)
            if let lastSeen {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(verbatim: Self.lastSeenLine(lastSeen, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if canWake {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    if isSilentLongEnough(now: context.date) { wakeArea }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task(id: network.generation) { await checkNetwork() }
    }

    /// Silent at least as long as the chosen delay
    private func isSilentLongEnough(now: Date) -> Bool {
        let since = lastSeen ?? offlineSince ?? now
        return now.timeIntervalSince(since) >= TimeInterval(wakeDelay)
    }

    @ViewBuilder private var wakeArea: some View {
        if onNetwork == false {
            Label("This device is not on the server's network. Connect to its Wi-Fi, and Wake up appears.",
                  systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.top, 4)
        } else {
            wakeButton
        }
    }

    private func checkNetwork() async {
        guard canWake, let node = WakeOnLANAvailability.target(in: deployment) else { return }
        onNetwork = await LocalNetworkCheck.isOnNetwork(of: node, broadcast: deployment.wakeOnLANBroadcast)
    }

    private var wakeButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                wake()
            } label: {
                HStack(spacing: 8) {
                    if waking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "power")
                    }
                    Text("Wake up")
                }
                .font((compact ? Font.subheadline : .body).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 4 : 6)
            }
            .prominentActionButtonStyle()
            .controlSize(compact ? .regular : .large)
            .disabled(waking)
            if let wakeMessage {
                Text(verbatim: wakeMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.top, 4)
    }

    private func wake() {
        waking = true
        wakeMessage = nil
        Task { @MainActor in
            let model = DashboardViewModel(deployment: deployment)
            _ = await model.wakeUp(readIfMissing: false)
            wakeMessage = model.quickActionResult?.message
            waking = false
        }
    }

    static func lastSeenLine(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let ago = formatter.localizedString(for: min(date, now), relativeTo: now)
        return UIL10n.string("Last answered %@", ago)
    }
}
