import AgentControl
import ServerControl
import SwiftUI

enum SecurityBanDuration {
    static let untilLifted: TimeInterval = 10 * 365 * 24 * 3600
}

struct SecurityBlocklistView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var adding: AddTarget?
    @State private var confirmingUnban: HostSecurityDecisions.Decision?

    private enum AddTarget: Identifiable {
        case ban
        case allow
        var id: String { self == .ban ? "ban" : "allow" }
    }

    var body: some View {
        Form {
            allowlistSection
            decisionsSection
        }
        .navigationTitle("Blocked addresses")
        .pleaseWait(viewModel.securityListBusy)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.loadSecurityLists() }
        .refreshableWithShortcut { await viewModel.loadSecurityLists() }
        .bottomBarClearance()
        .sheet(item: $adding) { target in
            SecurityAddressSheet(
                title: target == .ban ? "Block an address" : "Never block",
                suggestions: suggestedAddresses,
                isBan: target == .ban) { value, duration, comment in
                    Task {
                        if target == .ban {
                            await viewModel.setBan(true, value: value, duration: duration,
                                                   reason: comment)
                        } else {
                            await viewModel.setAllowed(true, value: value, comment: comment,
                                                       duration: duration)
                        }
                    }
                }
        }
        .alert("Lift this block?", isPresented: Binding(
            get: { confirmingUnban != nil },
            set: { if !$0 { confirmingUnban = nil } })) {
            Button("Lift") {
                if let decision = confirmingUnban {
                    Task {
                        await viewModel.setBan(false, value: decision.value,
                                               decisionID: decision.decisionID)
                    }
                }
                confirmingUnban = nil
            }
            Button("Cancel", role: .cancel) { confirmingUnban = nil }
        } message: {
            if let decision = confirmingUnban {
                Text("\(decision.value) can reach this server again. It will be blocked again if it repeats what it was blocked for — protect it below to stop that.")
            }
        }
    }

    // MARK: - Never block

    @ViewBuilder private var allowlistSection: some View {
        Section {
            switch viewModel.securityAllowlist {
            case .none:
                ProgressView().controlSize(.small)

            case .some(let list) where !list.isSupported:
                Label("This server's CrowdSec is too old to keep an allowlist. Updating the protection adds it.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)

            case .some(let list):
                Button {
                    adding = .allow
                } label: {
                    Label("Protect an address", systemImage: "checkmark.shield")
                }
                .disabled(viewModel.securityListBusy)
                ForEach(list.entries) { entry in
                    allowedRow(entry)
                }
                if list.entries.isEmpty {
                    Text("No address is protected yet.")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            InfoSectionHeader("Never blocked", note: "Addresses on this list are never blocked by this server, whatever they do — the one setting that helps BEFORE a block happens. Once an address is blocked, every connection from it is dropped, including this app's, and it can only be released from somewhere else. Protect the network you administer the server from.")
        } footer: {
            if !viewModel.securityListFailure.isEmpty {
                Text(verbatim: viewModel.securityListFailure)
                    .foregroundStyle(.red)
            }
        }
    }

    private func allowedRow(_ entry: HostSecurityAllowlist.Entry) -> some View {
        LabeledContent {
            Button("Remove", role: .destructive) {
                Task { await viewModel.setAllowed(false, value: entry.value) }
            }
            .buttonStyle(.borderless)
            .dangerTint()
            .disabled(viewModel.securityListBusy)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.value)
                    .monospacedDigit()
                if !entry.comment.isEmpty {
                    Text(verbatim: entry.comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Blocked right now

    @ViewBuilder private var decisionsSection: some View {
        Section {
            switch viewModel.securityDecisions {
            case .none:
                ProgressView().controlSize(.small)

            case .some(let lists) where !lists.isPresent:
                Text("This server's protection could not be reached.")
                    .foregroundStyle(.secondary)

            case .some(let lists):
                Button {
                    adding = .ban
                } label: {
                    Label("Block an address", systemImage: "hand.raised")
                }
                .disabled(viewModel.securityListBusy)
                if lists.communityCount > 0 {
                    LabeledContent("Community blocklist") {
                        Text("\(lists.communityCount) addresses")
                            .foregroundStyle(.secondary)
                    }
                }
                if lists.decisions.isEmpty {
                    Text("Nothing is blocked by this server right now.")
                        .foregroundStyle(.secondary)
                }
                ForEach(lists.decisions) { decision in
                    decisionRow(decision)
                }
            }
        } header: {
            InfoSectionHeader("Blocked by this server", note: "What this server decided on its own, from its own logs, plus anything blocked by hand. Blocks expire on their own — the time left is on each row. The community blocklist is counted separately: those addresses were reported by other CrowdSec installations and cannot be lifted here.")
        }
    }

    private func decisionRow(_ decision: HostSecurityDecisions.Decision) -> some View {
        Button {
            confirmingUnban = decision
        } label: {
            LabeledContent {
                Text(verbatim: decision.expiresIn)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if !CountryCatalog.flag(decision.country).isEmpty {
                            Text(verbatim: CountryCatalog.flag(decision.country))
                                .accessibilityLabel(Text(verbatim:
                                    CountryCatalog.name(for: decision.country)))
                        }
                        Text(verbatim: decision.value)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        if decision.isManual {
                            Text("by hand")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(verbatim: [decision.readableReason, decision.asName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.securityListBusy)
    }

    private var suggestedAddresses: [String] {
        let connected = viewModel.securityDecisions?.sshClientIPs
            ?? viewModel.securityAllowlist?.sshClientIPs
            ?? []
        let allowed = viewModel.securityAllowlist?.entries.map(\.value) ?? []
        return connected.filter { !allowed.contains($0) }
    }
}

struct SecurityAddressSheet: View {
    let title: LocalizedStringKey
    let suggestions: [String]
    let isBan: Bool
    let onSubmit: (String, TimeInterval, String) -> Void

    @State private var value = ""
    @State private var comment = ""
    @State private var hours: Double = 4
    @State private var forever = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("203.0.113.9 or 203.0.113.0/24", text: $value)
                        .monospacedDigit()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Address")
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions, id: \.self) { address in
                            Button {
                                value = address
                            } label: {
                                LabeledContent {
                                    if value == address {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                } label: {
                                    Text(verbatim: address).monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        InfoSectionHeader("Connected now", note: "Addresses with an open SSH session on the server right now — this device's among them. The server can see them; this app cannot, because it reaches the server through a tunnel.")
                    }
                }

                Section {
                    Toggle(isBan ? "Until lifted" : "Forever", isOn: $forever)
                    if !forever {
                        Stepper(value: $hours, in: 1...168, step: 1) {
                            Text("\(Int(hours)) h")
                        }
                    }
                    TextField(isBan ? "Reason (optional)" : "Note (optional)", text: $comment)
                } header: {
                    Text("How long")
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isBan ? "Block" : "Protect") {
                        onSubmit(value.trimmingCharacters(in: .whitespaces),
                                 forever ? (isBan ? SecurityBanDuration.untilLifted : 0)
                                         : hours * 3600,
                                 comment.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
