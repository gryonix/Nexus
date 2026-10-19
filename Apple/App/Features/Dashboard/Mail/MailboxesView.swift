import ServerControl
import ServiceCatalog
import SwiftUI

/// Mailbox management for the docker-mailserver engine
struct MailboxesView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var showAdd = false
    @State private var pendingAdd: PendingMailbox?
    @State private var passwordTarget: Mailbox?
    @State private var pendingPassword: PendingMailbox?
    @State private var pendingDeletion: Mailbox?

    private struct PendingMailbox {
        let address: String
        let password: String
    }

    private var domains: [String] {
        [viewModel.deployment.domain] + viewModel.deployment.additionalDomains
    }

    var body: some View {
        CardList {
            Section {
                content
            } header: {
                InfoSectionHeader("Mailboxes", note: "Each mailbox is an account on the mail server: the same address and password are used to send and to receive. The first one was created during the installation — its password is under Login & Passwords.")
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Add mailbox", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Mail")
        .raisedNavigationTitle()
        .refreshableWithShortcut { await viewModel.loadMailboxes() }
        .task {
            if case .idle = viewModel.mailboxes { await viewModel.loadMailboxes() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Label("Add mailbox", systemImage: "plus")
                }
            }
        }
        // Armed in the sheet, started once it has closed.
        .sheet(isPresented: $showAdd, onDismiss: {
            guard let pending = pendingAdd else { return }
            pendingAdd = nil
            Task { await viewModel.addMailbox(address: pending.address, password: pending.password) }
        }) {
            MailboxEditorSheet(
                mode: .create(domains: domains),
                onCancel: { showAdd = false },
                onConfirm: { address, password in
                    pendingAdd = PendingMailbox(address: address, password: password)
                    showAdd = false
                })
        }
        .sheet(item: $passwordTarget, onDismiss: {
            guard let pending = pendingPassword else { return }
            pendingPassword = nil
            Task {
                await viewModel.setMailboxPassword(address: pending.address,
                                                   password: pending.password)
            }
        }) { mailbox in
            MailboxEditorSheet(
                mode: .changePassword(address: mailbox.address),
                onCancel: { passwordTarget = nil },
                onConfirm: { address, password in
                    pendingPassword = PendingMailbox(address: address, password: password)
                    passwordTarget = nil
                })
        }
        .confirmationDialog("Delete this mailbox?",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { mailbox in
            Button("Delete", role: .destructive) {
                let target = mailbox.address
                pendingDeletion = nil
                Task { await viewModel.deleteMailbox(address: target) }
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { mailbox in
            Text("\(mailbox.address) and every message in it are deleted from the server. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.mailboxes {
        case .loaded(let mailboxes):
            if mailboxes.isEmpty {
                Text("No mailboxes yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mailboxes) { mailbox in
                    row(mailbox)
                }
            }
        case .loading, .idle:
            HStack { Text("Loading…"); Spacer(); ProgressView().controlSize(.small) }
        case .failed(let message):
            Label(message, systemImage: HealthLevel.critical.systemImageName)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func row(_ mailbox: Mailbox) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: mailbox.address)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = mailbox.detail {
                    // Straight from the server (quota and usage) — display only.
                    Text(verbatim: detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !mailbox.isManageable {
                    Text("Created outside the app — manage it on the server")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                passwordTarget = mailbox
            } label: {
                Label("Change password", systemImage: "key.horizontal")
                    .labelStyle(.iconOnly)
            }
            .glassIconButtonStyle()
            .disabled(!mailbox.isManageable)
            Button(role: .destructive) {
                pendingDeletion = mailbox
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .dangerTint()
            .glassIconButtonStyle()
            .disabled(!mailbox.isManageable)
        }
    }
}

/// Creates a mailbox or replaces its password
struct MailboxEditorSheet: View {
    enum Mode {
        case create(domains: [String])
        case changePassword(address: String)
    }

    let mode: Mode
    let onCancel: () -> Void
    let onConfirm: (String, String) -> Void

    @State private var localPart = ""
    @State private var domain = ""
    @State private var password = ""
    @State private var isRevealed = false

    /// The address as the wrapper will see it
    private var address: String {
        switch mode {
        case .create:
            return "\(localPart.trimmingCharacters(in: .whitespaces))@\(domain)"
        case .changePassword(let address):
            return address
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var canSubmit: Bool {
        guard password.count >= 8 else { return false }
        guard isCreating else { return true }
        return CommandCatalog.DockerMailserver.isValidAddress(address)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCreating {
                    Section {
                        addressFields
                    } header: {
                        InfoSectionHeader("Address", note: "Latin letters, digits and . _ + - only — this is what the mail server accepts.")
                    }
                } else {
                    Section("Mailbox") {
                        Text(verbatim: address)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Section {
                    passwordField
                    Button {
                        password = MailboxPassword.generate()
                        isRevealed = true
                    } label: {
                        Label("Generate a password", systemImage: "wand.and.stars")
                    }
                    .rowActionButtonStyle()
                    if !password.isEmpty {
                        Button {
                            copy(password)
                        } label: {
                            Label("Copy password", systemImage: "doc.on.doc")
                        }
                        .rowActionButtonStyle()
                    }
                } header: {
                    InfoSectionHeader("Password", note: "At least 8 characters. It is sent to the server over the existing SSH connection and stored only there — the app never keeps a copy, so write it down or copy it now.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 460, minHeight: 380)
            #endif
            .navigationTitle(isCreating ? "New Mailbox" : "New Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { onConfirm(address, password) }
                        .disabled(!canSubmit)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear {
                if case .create(let domains) = mode, domain.isEmpty {
                    domain = domains.first ?? ""
                }
            }
        }
    }

    private var confirmTitle: LocalizedStringKey {
        isCreating ? "Create" : "Change"
    }

    @ViewBuilder
    private var addressFields: some View {
        TextField("Mailbox name", text: $localPart)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            #endif
        if case .create(let domains) = mode {
            if domains.count > 1 {
                WrappingPicker("Domain", selection: $domain) {
                    ForEach(domains, id: \.self) { candidate in
                        Text(verbatim: candidate).tag(candidate)
                    }
                }
            } else {
                HStack {
                    Text("Domain")
                    Spacer()
                    Text(verbatim: domains.first ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        HStack {
            if isRevealed {
                TextField("Password", text: $password)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            } else {
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
            }
            Button {
                isRevealed.toggle()
            } label: {
                Label(isRevealed ? "Hide the password" : "Show the password",
                      systemImage: isRevealed ? "eye.slash" : "eye")
                    .labelStyle(.iconOnly)
            }
            .glassIconButtonStyle()
        }
    }

    private func copy(_ value: String) {
        SecretPasteboard.copy(value)
    }
}

/// Passwords offered for a new mailbox
enum MailboxPassword {
    static func generate(length: Int = 20) -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in
            alphabet[Int(generator.next(upperBound: UInt64(alphabet.count)))]
        })
    }
}
