import SwiftUI

struct DNSAPISettingsView: View {
    @ObservedObject private var credentials = DNSCredentials.shared
    @State private var editing: DNSCredentialEdit?
    @State private var hasToken: [String: Bool] = [:]
    @AppStorage("dns.credentials.sort") private var sortRaw = DNSCredentialSort.added.rawValue

    private var sort: DNSCredentialSort {
        DNSCredentialSort(rawValue: sortRaw) ?? .added
    }

    private var rows: [DNSCredential] {
        sort.apply(to: credentials.all)
    }

    var body: some View {
        CardList {
            Section {
                ForEach(rows) { credential in
                    Button {
                        credentials.selectedID = credential.id
                    } label: {
                        row(credential)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await credentials.remove(credential.id)
                                await refresh()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .dangerTint()
                    }
                }
                Button {
                    editing = DNSCredentialEdit(credential: nil)
                } label: {
                    Label("Add a token…", systemImage: "plus")
                }
                .rowActionButtonStyle()
            } footer: {
                if credentials.all.isEmpty {
                    Text("No DNS token yet. Add one to publish the generated records straight into your zone instead of exporting a zone file and importing it by hand.")
                } else {
                    Text("Tap a token to publish with it; the pencil holds the token itself, the name and which provider it belongs to.")
                }
            }
        }
        .navigationTitle("DNS API")
        .raisedNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    WrappingPicker("Sort", selection: $sortRaw) {
                        ForEach(DNSCredentialSort.allCases) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .disabled(credentials.all.count < 2)
            }
        }
        .task { await refresh() }
        .sheet(item: $editing) { edit in
            DNSCredentialEditor(credential: edit.credential) { Task { await refresh() } }
        }
    }

    private func row(_ credential: DNSCredential) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: credential.name)
                HStack(spacing: 6) {
                    Text(verbatim: credential.kind.displayName)
                    Text(verbatim: "·")
                    Text(hasToken[credential.id] == true
                         ? "A token is stored" : "No token stored")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if credential.id == credentials.selectedID {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
            Button {
                editing = DNSCredentialEdit(credential: credential)
            } label: {
                Image(systemName: "pencil")
            }
            .glassIconButtonStyle()
            .accessibilityLabel("Edit this token")
        }
        .contentShape(Rectangle())
    }

    private func refresh() async {
        await credentials.adoptStoredTokensIfNeeded()
        var found: [String: Bool] = [:]
        for credential in credentials.all {
            found[credential.id] = await DNSCredentialTokenStore.load(credential) != nil
        }
        hasToken = found
    }
}

/// The order the one list is drawn in
enum DNSCredentialSort: String, CaseIterable, Identifiable {
    case added
    case provider

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .added: return "As added"
        case .provider: return "By provider"
        }
    }

    func apply(to credentials: [DNSCredential]) -> [DNSCredential] {
        switch self {
        case .added:
            return credentials
        case .provider:
            return credentials.sorted {
                $0.kind.displayName == $1.kind.displayName
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.kind.displayName < $1.kind.displayName
            }
        }
    }
}

private struct DNSCredentialEdit: Identifiable {
    let credential: DNSCredential?
    var id: String { credential?.id ?? "new" }
}

private struct DNSCredentialEditor: View {
    let credential: DNSCredential?
    let onSave: () -> Void

    @ObservedObject private var credentials = DNSCredentials.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: DNSProviderKind
    @State private var draft = ""
    @State private var tunnelDraft = ""
    @State private var hasToken = false
    @State private var hasTunnel = false

    init(credential: DNSCredential?, onSave: @escaping () -> Void) {
        self.credential = credential
        self.onSave = onSave
        _name = State(initialValue: credential.flatMap {
            DNSCredentials.shared.storedName(of: $0.id)
        } ?? "")
        _kind = State(initialValue: credential?.kind ?? .cloudflare)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    WrappingPicker("Provider", selection: $kind) {
                        ForEach(DNSProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                }
                Section {
                    SecureField(hasToken ? "Replace the token" : kind.tokenFieldLabel,
                                text: $draft)
                        .textContentType(.password)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    if hasToken, let credential {
                        Button("Forget this token", role: .destructive) {
                            Task {
                                await DNSCredentialTokenStore.clear(credential)
                                hasToken = false
                            }
                        }
                        .dangerTint()
                        .rowActionButtonStyle()
                    }
                } header: {
                    InfoSectionHeader("Token", note: kind.setupHint)
                }
                if kind == .cloudflare {
                    Section {
                        SecureField(hasTunnel ? "Replace the token" : "API token",
                                    text: $tunnelDraft)
                        if hasTunnel, let credential {
                            Button("Forget this token", role: .destructive) {
                                Task {
                                    await DNSCredentialTokenStore.clearTunnelToken(credential)
                                    hasTunnel = false
                                }
                            }
                            .dangerTint()
                            .rowActionButtonStyle()
                        }
                    } header: {
                        InfoSectionHeader("Tunnels", note: "Needs Account · Cloudflare Tunnel · Edit. A tunnel belongs to the account, which is why this is a second token and not the first one with more rights.")
                    }
                }
            }
            .navigationTitle(name.isEmpty ? kind.displayName : name)
            .raisedNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                }
            }
            .task {
                guard let credential else { return }
                hasToken = await DNSCredentialTokenStore.load(credential) != nil
                hasTunnel = await DNSCredentialTokenStore.loadTunnelToken(credential) != nil
            }
        }
    }

    private func save() {
        let chosen = kind
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tunnel = tunnelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = credential ?? credentials.add(named: name, kind: chosen)
        Task {
            await DNSCredentialTokenStore.move(target, to: chosen)
            var saved = target
            saved.kind = chosen
            if !typed.isEmpty { try? await DNSCredentialTokenStore.save(typed, for: saved) }
            if !tunnel.isEmpty, chosen == .cloudflare {
                try? await DNSCredentialTokenStore.saveTunnelToken(tunnel, for: saved)
            }
            credentials.update(target.id, name: name, kind: chosen)
            onSave()
        }
        dismiss()
    }
}
