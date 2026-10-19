import AgentControl
import ServerControl
import SwiftUI

/// Key-only login, per account on the host
struct SSHAccessView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var confirming: PendingChange?

    /// What the tapped switch would do
    private struct PendingChange: Identifiable {
        let everyone: Bool
        let users: [String]
        let opening: Bool
        let account: String
        var id: String { "\(everyone)|\(account)|\(opening)" }
    }

    var body: some View {
        Form {
            everyoneSection
            accountsSection
        }
        .navigationTitle("SSH access")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { reloadButton }
        .refreshableWithShortcut { await viewModel.loadSSHUsers() }
        .task { await load() }
        .alert(item: $confirming) { change in
            Alert(title: Text(change.opening ? "Allow password login again?"
                                             : "Turn off password login?"),
                  message: Text(message(for: change)),
                  primaryButton: .destructive(Text(change.opening ? "Allow" : "Turn Off")) {
                      Task { await apply(change) }
                  },
                  secondaryButton: .cancel())
        }
    }

    private var reloadButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await viewModel.loadSSHUsers() }
            } label: {
                Label("Ask the server again", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isWorkingOnSSHUsers)
        }
    }

    private func load() async {
        guard viewModel.sshUsers == nil else { return }
        await viewModel.loadSSHUsers()
    }

    // MARK: - Every account at once

    @ViewBuilder private var everyoneSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.sshUsers?.isClosedForEveryone ?? false },
                set: { wanted in
                    confirming = PendingChange(everyone: wanted, users: [], opening: !wanted,
                                               account: "")
                }
            )) {
                Label("Key login only for everyone", systemImage: "lock.shield.fill")
            }
            .disabled(viewModel.isWorkingOnSSHUsers || !(viewModel.sshUsers?.isKnown ?? false))
        } header: {
            InfoSectionHeader("Every account", note: "With this on, the whole machine refuses SSH passwords. With it off, each account below decides for itself — that is one `Match User` block in the server's SSH configuration, written and taken back by this app.")
        } footer: {
            if let detail = viewModel.sshUsers?.detail, !detail.isEmpty {
                Text(verbatim: detail)
            }
        }
    }

    // MARK: - One account at a time

    @ViewBuilder private var accountsSection: some View {
        Section {
            switch viewModel.sshUsers {
            case .none:
                HStack {
                    Text("Accounts")
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            case .some(let answer) where !answer.isKnown:
                Label("This server did not say what accounts it has. The agent may be too old for it.",
                      systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .some(let answer) where answer.users.isEmpty:
                Text("This server named no account anyone could sign in as.")
                    .foregroundStyle(.secondary)
            case .some(let answer):
                ForEach(answer.users) { user in
                    accountRow(user, in: answer)
                }
                addKeyRow
            }
        } header: {
            InfoSectionHeader("Accounts", note: "An account with no key of its own cannot be closed: turning passwords off around it would leave nobody a way in, and the server refuses to do it. Add a key to that account first.")
        } footer: {
            accountsFooter
        }
    }

    @ViewBuilder
    private func accountRow(_ user: SSHUserAccess, in answer: SSHUsers) -> some View {
        Toggle(isOn: Binding(
            get: { user.isClosed },
            set: { wanted in
                var names = Set(answer.closedNames)
                if wanted { names.insert(user.name) } else { names.remove(user.name) }
                confirming = PendingChange(everyone: false, users: names.sorted(),
                                           opening: !wanted, account: user.name)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: user.name).font(.body.monospaced())
                Text(caption(for: user))
                    .font(.caption)
                    .foregroundStyle(user.wouldLockOut ? Color.orange : Color.secondary)
            }
        }
        .disabled(viewModel.isWorkingOnSSHUsers || !user.isKnown
                  || (user.wouldLockOut && !user.isClosed)
                  || answer.isClosedForEveryone)
    }

    private func caption(for user: SSHUserAccess) -> LocalizedStringKey {
        if !user.isKnown { return "The server did not say" }
        if user.isLoginUser { return "The account this app signs in with" }
        if user.wouldLockOut { return "No key of its own — add one before closing it" }
        return user.isClosed ? "Key login only" : "Password login is open"
    }

    /// Nothing can be closed without the app's own key
    @ViewBuilder private var addKeyRow: some View {
        if let answer = viewModel.sshUsers, answer.isKnown, answer.host.isKnown,
           !answer.host.appKeyPresent {
            Button {
                Task {
                    if await viewModel.grantAppKeyToLoginAccount() { await viewModel.loadSSHUsers() }
                }
            } label: {
                Label("Add This App's Key", systemImage: "key.horizontal")
            }
            .rowActionButtonStyle()
            .disabled(viewModel.isChangingSSHPassword)
        }
    }

    @ViewBuilder private var accountsFooter: some View {
        if viewModel.sshUsers?.isClosedForEveryone == true {
            Text("Every account is closed by the switch above. Turn it off to decide account by account.")
        }
    }

    // MARK: - Doing it

    private func apply(_ change: PendingChange) async {
        await viewModel.setKeyOnlySSHUsers(everyone: change.everyone, users: change.users)
    }

    private func message(for change: PendingChange) -> String {
        if change.opening {
            return UIL10n.string("Passwords are what automated attacks try, thousands of times a day. Turn this back on only if you need to sign in to this machine without a key.")
        }
        if change.everyone {
            return UIL10n.string("This server will only accept SSH key logins, for every account on it. This app's key is on %@, and it stays — but anyone who signs in with a password will not be able to any more.",
                                 viewModel.sshLoginUser)
        }
        return UIL10n.string("%@ will only be able to sign in with an SSH key. The account keeps the keys it already has.",
                             change.account)
    }
}
