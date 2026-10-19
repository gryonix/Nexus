import AgentClient
import AgentControl
import SwiftUI
import ServerControl
import ServiceCatalog

struct InstallReportView: View {
    let deployment: Deployment

    @AppStorage(SecuritySettings.gateRevealKey) private var gateReveal = true
    @State private var reports: [StoredInstallReport] = []
    @State private var accounts: [EditableAccount] = []
    /// What the server said, and what it could not say
    @State private var syncState: SyncState = .localOnly
    @State private var revealed: Set<String> = []
    @State private var copiedFieldID: String?
    @State private var justSaved = false
    @State private var isLoading = true

    private var showsHost: Bool { reports.count > 1 }

    var body: some View {
        CardList {
            if isLoading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if reports.isEmpty && accounts.isEmpty {
                Section {
                    Text("No saved report yet. It is captured automatically when you install from this device; re-run the installation to fill it in.")
                        .foregroundStyle(.secondary)
                }
            } else if accounts.isEmpty {
                Section {
                    Text("No sign-in details in this report.")
                        .foregroundStyle(.secondary)
                }
            } else {
                syncSection
                ForEach($accounts) { $account in
                    Section {
                        accountRows($account)
                    } header: {
                        Text(verbatim: header(for: account))
                    }
                }
            }
        }
        .navigationTitle(Text("Login & Passwords"))
        .raisedNavigationTitle()
        .toolbar {
            if !accounts.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Label(justSaved ? UIL10n.string("Saved") : UIL10n.string("Save"),
                              systemImage: justSaved ? "checkmark" : "square.and.arrow.down")
                    }
                    .disabled(justSaved)
                }
            }
        }
        .task { await load() }
    }

    /// One line at the top saying where these values live
    @ViewBuilder
    private var syncSection: some View {
        switch syncState {
        case .synced:
            Section {
                Label("Kept on the server — these are the same on every device paired with it.",
                      systemImage: "checkmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .localOnly:
            Section {
                Label("Saved on this device only. Install the agent on this server to share them with your other devices.",
                      systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .signedOut:
            Section {
                Label("This device has been signed out of the server, so its saved passwords were cleared. Open Paired Devices to sign in again.",
                      systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .unidentified:
            Section {
                Label("The server will not answer this device, because it cannot say which device it is. Nothing was cleared: for now these values are local to this device.",
                      systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    enum SyncState: Equatable {
        case synced
        case localOnly
        case signedOut
        case unidentified
        case failed(String)
    }

    // MARK: - Rows

    @ViewBuilder
    private func accountRows(_ account: Binding<EditableAccount>) -> some View {
        let a = account.wrappedValue
        if let website = a.website {
            displayRow(label: UIL10n.string("Website"), value: website, id: a.id + "site")
        }
        editableRow(label: a.isVaultwarden ? UIL10n.string("Email") : UIL10n.string("Login"),
                    text: account.login, id: a.id + "login", secure: false)
        editableRow(label: a.isVaultwarden ? UIL10n.string("Master password") : UIL10n.string("Password"),
                    text: account.password, id: a.id + "pw", secure: true)
        if a.hasToken {
            editableRow(label: UIL10n.string("Admin token"),
                        text: account.token, id: a.id + "token", secure: true)
        }
    }

    /// Read-only row (the site URL) with a copy button
    private func displayRow(label: String, value: String, id: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.callout.monospaced())
                    .lineLimit(1).truncationMode(.middle)
                    .revealsFullText(value)
                    .textSelection(.enabled)
            }
            Spacer()
            copyButton(value, id: id)
        }
    }

    /// Editable field
    private func editableRow(label: String, text: Binding<String>, id: String, secure: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
                Group {
                    if secure && !revealed.contains(id) {
                        SecureField("", text: text)
                    } else {
                        TextField("", text: text)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                }
                .font(.callout.monospaced())
                .textFieldStyle(.plain)
                .onChange(of: text.wrappedValue) { justSaved = false }
            }
            Spacer(minLength: 8)
            if secure {
                Button {
                    if revealed.contains(id) { revealed.remove(id) } else { reveal(id) }
                } label: {
                    Image(systemName: revealed.contains(id) ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .glassIconButtonStyle()
                .accessibilityLabel(Text(revealed.contains(id) ? "Hide" : "Reveal"))
            }
            copyButton(text.wrappedValue, id: id + "copy", secure: secure)
        }
    }

    private func copyButton(_ value: String, id: String, secure: Bool = false) -> some View {
        Button {
            gated(secure) { copy(value, fieldID: id) }
        } label: {
            Image(systemName: copiedFieldID == id ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copiedFieldID == id ? .green : .accentColor)
        }
        .glassIconButtonStyle()
        .disabled(value.isEmpty)
        .accessibilityLabel(Text("Copy"))
    }

    // MARK: - Data

    private func load() async {
        let deploymentID = deployment.id
        let built = await Task.detached(priority: .userInitiated) {
            () -> (reports: [StoredInstallReport], accounts: [EditableAccount]) in
            let reports = DeploymentReportStore(deploymentID: deploymentID).load()
            let overrides = AccessCredentialStore(deploymentID: deploymentID).load()
            var accounts: [EditableAccount] = []
            for report in reports {
                let sections = InstallReportParser.sections(from: report.text)
                for acc in SimpleAccount.accounts(from: sections) {
                    let key = AccessCredentialStore.key(host: report.host, title: acc.title)
                    let ovr = overrides[key]
                    let stampedAt = ovr?.updatedAt.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
                    accounts.append(EditableAccount(
                        host: report.host,
                        title: acc.title,
                        website: acc.website,
                        reportLogin: acc.login ?? "",
                        reportPassword: acc.password ?? "",
                        reportToken: acc.token ?? "",
                        login: ovr?.login ?? acc.login ?? "",
                        password: ovr?.password ?? acc.password ?? "",
                        token: ovr?.token ?? acc.token ?? "",
                        hasToken: acc.token != nil || (ovr?.token?.isEmpty == false),
                        isVaultwarden: acc.title.lowercased().hasPrefix("vaultwarden"),
                        updatedAt: stampedAt,
                        updatedBy: ovr?.updatedBy ?? ""
                    ))
                }
            }
            return (reports, accounts)
        }.value
        reports = built.reports
        accounts = built.accounts
        if #available(macOS 15.0, *), deployment.usesAgent {
            await syncWithServer()
        } else {
            syncState = .localOnly
        }
        isLoading = false
    }

    struct SyncOutcome: Equatable {
        var state: SyncState
        var clearsCache: Bool
    }

    @available(macOS 15.0, *)
    static func outcome(for fetched: AccessVault.Fetched) -> SyncOutcome? {
        if fetched.sessionExpired { return SyncOutcome(state: .signedOut, clearsCache: true) }
        if fetched.unidentified { return SyncOutcome(state: .unidentified, clearsCache: false) }
        guard fetched.reachedServer else {
            return SyncOutcome(state: fetched.failure.map(SyncState.failed) ?? .localOnly,
                               clearsCache: false)
        }
        return nil
    }

    @available(macOS 15.0, *)
    private func syncWithServer() async {
        let fetched = await AccessVault.fetch(deployment: deployment)
        if let outcome = Self.outcome(for: fetched) {
            if outcome.clearsCache {
                let deploymentID = deployment.id
                await Task.detached(priority: .userInitiated) {
                    AccessCredentialStore(deploymentID: deploymentID).delete()
                    DeploymentReportStore(deploymentID: deploymentID).delete()
                }.value
                accounts = []
                reports = []
            }
            syncState = outcome.state
            return
        }
        accounts = Self.merged(local: accounts, remote: fetched.entries, deployment: deployment)
        syncState = .synced
    }

    static func merged(local: [EditableAccount],
                       remote: [Gryonixnexusd_V1_VaultEntry],
                       deployment: Deployment) -> [EditableAccount] {
        let localEntries = local.map(\.asVaultEntry)
        let winners = Dictionary(
            VaultMerge.resolved(local: localEntries, remote: remote).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var result = local.compactMap { account -> EditableAccount? in
            guard let winner = winners[account.id] else { return account }
            guard !winner.deleted else { return nil }
            var updated = account
            updated.login = winner.login
            updated.password = winner.password
            updated.token = winner.token
            updated.hasToken = updated.hasToken || !winner.token.isEmpty
            updated.updatedAt = winner.updatedAt
            updated.updatedBy = winner.updatedBy
            updated.markLoadedValues()
            return updated
        }
        let known = Set(local.map(\.id))
        for entry in winners.values.sorted(by: { $0.id < $1.id })
        where !known.contains(entry.id) && !entry.deleted && entry.serviceSecret.isEmpty {
            result.append(EditableAccount(fromServer: entry))
        }
        return result
    }

    private func save() async {
        let now = Date()
        let writer = DeviceIdentity.uid
        var overrides: [String: AccessCredential] = [:]
        for a in accounts {
            var cred = AccessCredential(
                login: a.login != a.reportLogin && !a.login.isEmpty ? a.login : nil,
                password: a.password != a.reportPassword && !a.password.isEmpty ? a.password : nil,
                token: a.token != a.reportToken && !a.token.isEmpty ? a.token : nil
            )
            if !cred.isEmpty {
                if a.isChanged {
                    cred.updatedAt = now
                    cred.updatedBy = writer
                } else {
                    cred.updatedAt = a.updatedAt > 0
                        ? Date(timeIntervalSince1970: Double(a.updatedAt) / 1000) : nil
                    cred.updatedBy = a.updatedBy.isEmpty ? nil : a.updatedBy
                }
                overrides[a.id] = cred
            }
        }
        let deploymentID = deployment.id
        let toSave = overrides
        await Task.detached(priority: .userInitiated) {
            AccessCredentialStore(deploymentID: deploymentID).save(toSave)
        }.value

        if #available(macOS 15.0, *), deployment.usesAgent {
            let outgoing = Self.entriesToPush(accounts, at: now, writer: writer)
            if !outgoing.isEmpty {
                let pushed = await AccessVault.push(outgoing, deployment: deployment)
                syncState = pushed
                    ? .synced
                    : .failed(UIL10n.string("Saved on this device. The server could not be reached, so your other devices will see this after the next sync."))
            }
        }
        for index in accounts.indices { accounts[index].markLoadedValues() }
        justSaved = true
    }

    static func entriesToPush(_ accounts: [EditableAccount], at now: Date,
                              writer: String) -> [Gryonixnexusd_V1_VaultEntry] {
        accounts.compactMap { account in
            if account.isChanged {
                return AccessVaultEntry.make(id: account.id, host: account.host,
                                             title: account.title, website: account.website,
                                             login: account.login, password: account.password,
                                             token: account.token,
                                             updatedAt: now, updatedBy: writer)
            }
            guard !account.isEmptyCredential else { return nil }
            return AccessVaultEntry.make(id: account.id, host: account.host,
                                         title: account.title, website: account.website,
                                         login: account.login, password: account.password,
                                         token: account.token,
                                         updatedAt: nil, updatedBy: "agent")
        }
    }

    private func header(for account: EditableAccount) -> String {
        showsHost ? "\(hostTitle(account.host)) · \(account.title)" : account.title
    }

    private func hostTitle(_ host: String) -> String {
        switch host {
        case "vps": return "VPS"
        case "home": return UIL10n.string("Local server")
        case "single": return UIL10n.string("Server")
        default:
            guard let id = UUID(uuidString: host),
                  let node = deployment.nodes.first(where: { $0.id == id }) else {
                return UIL10n.string("Server")
            }
            return node.name.isEmpty ? node.endpoint.host : node.name
        }
    }

    private func reveal(_ id: String) {
        gated(true) { revealed.insert(id) }
    }

    private func gated(_ secure: Bool, _ action: @escaping () -> Void) {
        guard secure, gateReveal else { action(); return }
        Task { @MainActor in
            if await BiometricGate.authenticate(reason: UIL10n.string("Unlock to view access & passwords")) {
                action()
            }
        }
    }

    private func copy(_ string: String, fieldID: String) {
        SecretPasteboard.copy(string)
        copiedFieldID = fieldID
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedFieldID == fieldID { copiedFieldID = nil }
        }
    }
}

/// Editable state for one web-login card
struct EditableAccount: Identifiable {
    let host: String
    let title: String
    let website: String?
    let reportLogin: String
    let reportPassword: String
    let reportToken: String
    var login: String
    var password: String
    var token: String
    var hasToken: Bool
    let isVaultwarden: Bool
    var updatedAt: Int64 = 0
    var updatedBy: String = ""
    private var loadedLogin: String = ""
    private var loadedPassword: String = ""
    private var loadedToken: String = ""

    var id: String { AccessCredentialStore.key(host: host, title: title) }

    var isChanged: Bool {
        login != loadedLogin || password != loadedPassword || token != loadedToken
    }

    /// Nothing worth sending
    var isEmptyCredential: Bool {
        login.isEmpty && password.isEmpty && token.isEmpty
    }

    mutating func markLoadedValues() {
        loadedLogin = login
        loadedPassword = password
        loadedToken = token
    }

    /// This device's copy as the schema sees it
    var asVaultEntry: Gryonixnexusd_V1_VaultEntry {
        AccessVaultEntry.make(id: id, host: host, title: title, website: website,
                          login: login, password: password, token: token,
                          updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1000),
                          updatedBy: updatedBy)
    }

    init(fromServer entry: Gryonixnexusd_V1_VaultEntry) {
        host = entry.host
        title = entry.title
        website = entry.website.isEmpty ? nil : entry.website
        reportLogin = ""
        reportPassword = ""
        reportToken = ""
        login = entry.login
        password = entry.password
        token = entry.token
        hasToken = !entry.token.isEmpty
        isVaultwarden = entry.title.lowercased().hasPrefix("vaultwarden")
        updatedAt = entry.updatedAt
        updatedBy = entry.updatedBy
        markLoadedValues()
    }

    init(host: String, title: String, website: String?, reportLogin: String,
         reportPassword: String, reportToken: String, login: String, password: String,
         token: String, hasToken: Bool, isVaultwarden: Bool,
         updatedAt: Int64 = 0, updatedBy: String = "") {
        self.host = host
        self.title = title
        self.website = website
        self.reportLogin = reportLogin
        self.reportPassword = reportPassword
        self.reportToken = reportToken
        self.login = login
        self.password = password
        self.token = token
        self.hasToken = hasToken
        self.isVaultwarden = isVaultwarden
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        markLoadedValues()
    }
}

/// A single login distilled from a report section
struct SimpleAccount: Identifiable {
    let title: String
    var website: String?
    var login: String?
    var password: String?
    var token: String?
    var id: String { title }

    static func accounts(from sections: [InstallReportParser.Section]) -> [SimpleAccount] {
        sections.compactMap(account(from:))
    }

    private static func account(from section: InstallReportParser.Section) -> SimpleAccount? {
        var account = SimpleAccount(title: section.title)
        for field in section.fields {
            if field.label == "URL" {
                account.website = cleanURL(field.value)
            } else if Labels.password.contains(field.label) {
                account.password = field.value
            } else if Labels.token.contains(field.label) {
                account.token = field.value
            } else if Labels.login.contains(field.label) {
                account.login = field.value
            }
        }
        // A service names its address its own way
        if account.website?.hasPrefix("http") != true {
            account.website = section.fields
                .first { $0.value.hasPrefix("http") }
                .map { cleanURL($0.value) }
        }
        guard account.website != nil || account.password != nil || account.token != nil else {
            return nil
        }
        return account
    }

    /// Strip the trailing " (directory: …)" annotation the report appends
    private static func cleanURL(_ value: String) -> String {
        if let idx = value.range(of: "  (") { return String(value[..<idx.lowerBound]) }
        return value
    }

    private enum Labels {
        static let password = Set(AppLanguage.allCases.flatMap {
            [L10nServices.passwordLabel($0), L10nServices.passwordGeneratedOnServerLabel($0)]
        })
        static let login = Set(AppLanguage.allCases.flatMap {
            [L10nServices.administratorLabel($0), L10nServices.mosquittoAccountsLabel($0)]
        })
        static let token = Set(AppLanguage.allCases.map { L10nServices.vaultwardenAdminTokenLabel($0) })
    }
}
