import AgentControl
import ServerControl
import SwiftUI

struct CrowdSecSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showAttempts = false
    @State private var confirmingSecurity: AgentSecurityOperations.Action?
    #if DEBUG
    /// Screenshot hook — see the probe on the "Automatic blocking" row
    @State private var showingAutoRules = false
    #endif
    @State private var reloading = false
    @State private var selecting = false
    /// The addresses ticked while `selecting`
    @State private var selected: Set<String> = []

    var body: some View {
        Form {
            if let status = viewModel.securityStatus, status.isPresent {
                statsSection(status)
                actionsSection(status)
            } else {
                unreadSection
            }
        }
        .navigationTitle("CrowdSec")
        .pleaseWait(viewModel.runningSecurityAction != nil || viewModel.securityListBusy,
                    detail: viewModel.securityActionProgress)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { reloadButton }
        .refreshableWithShortcut { await reload() }
        .task { await viewModel.loadSecurityAutoRules() }
        .alert(confirmingSecurity == .remove ? "Remove the protection?" : "Stop the protection?",
               isPresented: Binding(get: { confirmingSecurity != nil },
                                    set: { if !$0 { confirmingSecurity = nil } })) {
            Button(confirmingSecurity == .remove ? "Remove" : "Stop", role: .destructive) {
                if let action = confirmingSecurity {
                    Task { await viewModel.runSecurityAction(action) }
                }
                confirmingSecurity = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { confirmingSecurity = nil }
        } message: {
            if confirmingSecurity == .remove {
                Text("CrowdSec and its firewall bouncer are uninstalled from this server, and the addresses it is blocking right now are released with them. Nothing else on the server is touched. It can be installed again here.")
            } else {
                Text("This server stops watching its login and web logs, and the addresses it is blocking are released. Attacks are not blocked until it is started again — which does happen on the next restart of the machine, because the service stays enabled.")
            }
        }
    }

    /// The screen still opens before the server has answered
    @ViewBuilder private var unreadSection: some View {
        Section {
            if viewModel.securityStatus == nil || viewModel.isReadingSecurity {
                HStack {
                    Text("Security")
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            } else if viewModel.securityStatus?.isKnown == true {
                Label("Not set up", systemImage: "shield.slash")
                installButton
            } else {
                Label("Could not read", systemImage: "questionmark.circle")
            }
        } footer: {
            Text("This server's intrusion defence could not be reached — it may not be installed, or the agent may be too old to report it. Update the agent, or re-run setup.")
        }
    }

    private var installButton: some View {
        Button {
            Task { await viewModel.runSecurityAction(.install) }
        } label: {
            Label("Install Protection", systemImage: "shield.lefthalf.filled")
        }
        .rowActionButtonStyle()
        .disabled(viewModel.runningSecurityAction != nil)
    }

    private var reloadButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await reload() }
            } label: {
                Label("Ask the server again", systemImage: "arrow.clockwise")
            }
            .disabled(reloading)
        }
    }

    private func reload() async {
        reloading = true
        await viewModel.loadSecurity()
        await viewModel.loadSecurityAutoRules()
        reloading = false
    }

    // MARK: - Numbers and history

    @ViewBuilder
    private func statsSection(_ status: HostSecurityStatus) -> some View {
        Section {
            headerRow(status)
            statsGrid(status)
            NavigationLink {
                SecurityBlocklistView(viewModel: viewModel)
            } label: {
                Label("Blocked addresses", systemImage: "hand.raised")
            }
            NavigationLink {
                SecurityAutoRulesView(viewModel: viewModel)
            } label: {
                LabeledContent {
                    if let rules = viewModel.securityAutoRules {
                        Text(rules.isOn ? UIL10n.string("On") : UIL10n.string("Off"))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                } label: {
                    Label("Automatic blocking", systemImage: "shield.lefthalf.filled")
                }
            }
            #if DEBUG
            .navigationDestination(isPresented: $showingAutoRules) {
                SecurityAutoRulesView(viewModel: viewModel)
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_AUTORULES"] != nil
                else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                showingAutoRules = true
            }
            #endif
            if !status.recentBans.isEmpty {
                DisclosureGroup(isExpanded: $showAttempts) {
                    ForEach(status.recentBans) { ban in
                        attemptRow(ban)
                    }
                    selectionRow(status)
                } label: {
                    Text("Recent attempts")
                }
            }
        } footer: {
            if !status.isPresent {
                Text("This server's intrusion defence could not be reached — it may not be installed, or the agent may be too old to report it. Update the agent, or re-run setup.")
            }
        }
    }

    @ViewBuilder
    private func headerRow(_ status: HostSecurityStatus) -> some View {
        HStack {
            Label {
                Text(status.isHealthy ? "Protecting this server" : "Protection degraded")
            } icon: {
                Image(systemName: status.isHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(status.isHealthy ? Color.green : Color.orange)
            }
            Spacer()
            if !status.engineVersion.isEmpty {
                Text(verbatim: "CrowdSec \(status.engineVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Four numbers as tiles, so the screen needs no scrolling
    @ViewBuilder
    private func statsGrid(_ status: HostSecurityStatus) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                  alignment: .leading, spacing: 10) {
            statTile("Attacks stopped (24h)", value: "\(status.alertsLast24h)")
            if status.communityBlocklistIPs > 0 {
                statTile("Community blocklist",
                         value: Self.compact(status.communityBlocklistIPs))
            }
            if status.localBans > 0 {
                statTile("Blocked right now", value: "\(status.localBans)")
            }
            if status.packetsDropped > 0 {
                statTile("Packets dropped", value: Self.compact(status.packetsDropped))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statTile(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func attemptRow(_ ban: HostSecurityStatus.Ban) -> some View {
        HStack {
            if selecting {
                Image(systemName: selected.contains(ban.ip)
                        ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(ban.ip)
                                        ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: [Self.flag(ban.country), ban.ip].filter { !$0.isEmpty }.joined(separator: " "))
                    .monospacedDigit()
                Text(verbatim: HostSecurityStatus.Scenario(name: ban.scenario, count: 0).readableName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = ban.date {
                Text(date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .contentShape(Rectangle())
        .onTapGesture {
            guard selecting else { return }
            if selected.contains(ban.ip) { selected.remove(ban.ip) } else { selected.insert(ban.ip) }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                block(ban.ip, duration: Self.defaultBan)
            } label: {
                Label("Block", systemImage: "hand.raised")
            }
            .dangerTint()
        }
        #endif
        .contextMenu { attemptMenu(ban) }
        .disabled(viewModel.securityListBusy)
    }

    @ViewBuilder
    private func attemptMenu(_ ban: HostSecurityStatus.Ban) -> some View {
        Button {
            block(ban.ip, duration: Self.defaultBan)
        } label: {
            Label("Block for 4 hours", systemImage: "hand.raised")
        }
        Button {
            block(ban.ip, duration: 24 * 3600)
        } label: {
            Label("Block for 24 hours", systemImage: "hand.raised")
        }
        Button(role: .destructive) {
            block(ban.ip, duration: SecurityBanDuration.untilLifted)
        } label: {
            Label("Block until lifted", systemImage: "hand.raised.fill")
        }
        .dangerTint()
        if let subnet = Self.subnet(of: ban.ip) {
            Divider()
            Button(role: .destructive) {
                block(subnet, duration: 24 * 3600)
            } label: {
                Label {
                    Text("Block the whole \(subnet)")
                } icon: {
                    Image(systemName: "square.stack.3d.down.right")
                }
            }
            .dangerTint()
        }
        Divider()
        Button {
            Task { await viewModel.setAllowed(true, value: ban.ip) }
        } label: {
            Label("Never block", systemImage: "checkmark.shield")
        }
    }

    @ViewBuilder
    private func selectionRow(_ status: HostSecurityStatus) -> some View {
        if selecting {
            HStack {
                Button("Cancel") {
                    selecting = false
                    selected = []
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Select all") {
                    selected = Set(status.recentBans.map(\.ip))
                }
                .buttonStyle(.borderless)
                .disabled(selected.count == status.recentBans.count)
                Button(role: .destructive) {
                    blockSelected()
                } label: {
                    Text("Block \(selected.count)")
                }
                .buttonStyle(.borderless)
                .dangerTint()
                .disabled(selected.isEmpty || viewModel.securityListBusy)
            }
            .font(.callout)
        } else {
            Button {
                selecting = true
            } label: {
                Label("Select", systemImage: "checklist")
            }
            .font(.callout)
            .disabled(status.recentBans.isEmpty)
        }
    }

    private func block(_ value: String, duration: TimeInterval) {
        Task { await viewModel.setBan(true, value: value, duration: duration) }
    }

    private func blockSelected() {
        let addresses = selected.sorted()
        selecting = false
        selected = []
        Task {
            for address in addresses {
                await viewModel.setBan(true, value: address, duration: Self.defaultBan)
            }
        }
    }

    /// What CrowdSec itself bans for when nothing says otherwise
    private static let defaultBan: TimeInterval = 4 * 3600

    static func subnet(of address: String) -> String? {
        if address.contains(":") {
            let groups = address.split(separator: ":", omittingEmptySubsequences: false)
            guard groups.count >= 4 else { return nil }
            let prefix = groups.prefix(4)
            guard prefix.allSatisfy({ !$0.isEmpty && UInt16($0, radix: 16) != nil }) else {
                return nil
            }
            return prefix.joined(separator: ":") + "::/64"
        }
        let octets = address.split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return "\(octets[0]).\(octets[1]).\(octets[2]).0/24"
    }

    // MARK: - Running the protection

    @ViewBuilder
    private func actionsSection(_ status: HostSecurityStatus) -> some View {
        Section("Actions") {
            if let running = viewModel.runningSecurityAction {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.runningTitle(running))
                        if !viewModel.securityActionProgress.isEmpty {
                            Text(verbatim: viewModel.securityActionProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            } else {
                CompactActionGroup([
                    CompactAction("Update", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await viewModel.runSecurityAction(.update) }
                    },
                    CompactAction("Restart", systemImage: "arrow.clockwise") {
                        Task { await viewModel.runSecurityAction(.restart) }
                    },
                    status.engineRunning
                        ? CompactAction("Stop", systemImage: "pause.circle", role: .destructive) {
                            confirmingSecurity = .stop
                        }
                        : CompactAction("Start", systemImage: "play.circle") {
                            Task { await viewModel.runSecurityAction(.start) }
                        },
                    CompactAction("Remove", systemImage: "trash", role: .destructive) {
                        confirmingSecurity = .remove
                    }
                ])
                .listRowSeparator(.hidden)
                .padding(.vertical, 2)
            }
            if !viewModel.securityActionFailure.isEmpty {
                Label {
                    Text(verbatim: viewModel.securityActionFailure)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// What the spinner says it is doing
    private static func runningTitle(_ action: AgentSecurityOperations.Action) -> LocalizedStringKey {
        switch action {
        case .start: return "Starting protection…"
        case .stop: return "Stopping protection…"
        case .restart: return "Restarting protection…"
        case .update: return "Updating protection…"
        case .install: return "Installing protection…"
        case .remove: return "Removing protection…"
        }
    }

    /// 15737 → "15.7k", 128000 → "128k", 2.1M → "2.1M"
    private static func compact(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000:
            let k = Double(n) / 1_000
            return k < 100 ? String(format: "%.1fk", k) : "\(Int(k.rounded()))k"
        default:
            let m = Double(n) / 1_000_000
            return m < 100 ? String(format: "%.1fM", m) : "\(Int(m.rounded()))M"
        }
    }

    private static func flag(_ code: String) -> String {
        let upper = code.uppercased()
        guard upper.count == 2, upper.allSatisfy({ $0.isLetter && $0.isASCII }) else { return "" }
        return String(upper.unicodeScalars.compactMap {
            Unicode.Scalar(127_397 + $0.value)
        }.map(Character.init))
    }
}
