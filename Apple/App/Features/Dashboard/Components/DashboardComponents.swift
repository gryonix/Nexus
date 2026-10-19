import ServerControl
import SwiftUI

extension HealthLevel {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}

struct StatusRow<Value>: View {
    let title: LocalizedStringKey
    let state: Loadable<Value>
    let health: (Value) -> HealthLevel
    let text: (Value) -> String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            switch state {
            case .idle:
                Text("—").foregroundStyle(.secondary)
            case .loading:
                ProgressView().controlSize(.small)
            case .loaded(let value):
                Image(systemName: health(value).systemImageName)
                    .foregroundStyle(health(value).color)
                    .font(.callout)
                    .accessibilityLabel(text(value))
            case .failed(let message):
                Label(message, systemImage: HealthLevel.critical.systemImageName)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        #if os(iOS)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        #endif
    }
}

struct CompactActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    private var tint: Color { role == .destructive ? .red : .accentColor }

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .revealsFullText(title)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .glassTileButtonStyle()
        .tint(tint)
        .controlSize(.small)
    }
}

/// One button in a `CompactActionGroup`
struct CompactAction {
    let title: LocalizedStringKey
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String,
         role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
}

struct CompactActionGroup: View {
    let actions: [CompactAction]

    init(_ actions: [CompactAction]) {
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, action in
                        CompactActionButton(title: action.title,
                                            systemImage: action.systemImage,
                                            role: action.role,
                                            action: action.action)
                    }
                }
            }
        }
    }

    private var rows: [[CompactAction]] {
        guard actions.count > 3 else { return actions.isEmpty ? [] : [actions] }
        return stride(from: 0, to: actions.count, by: 2).map {
            Array(actions[$0..<min($0 + 2, actions.count)])
        }
    }
}

/// Disk/memory bar: native ProgressView plus formatted byte counts
struct UsageBarRow: View {
    let title: LocalizedStringKey
    let usedBytes: Int64
    let totalBytes: Int64

    private var fraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    private var tint: Color {
        switch fraction {
        case ..<0.75: return .green
        case ..<0.9: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text("\(Self.format(usedBytes)) / \(Self.format(totalBytes)) · \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: min(fraction, 1))
                .tint(tint)
        }
        .padding(.vertical, 2)
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}

/// WireGuard interface + peers, colored by handshake freshness
struct WGStatusView: View {
    let status: WGStatus
    var displayName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(displayName ?? status.interface.name, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.callout.weight(.medium))
                Spacer()
                if let port = status.interface.listeningPort {
                    Text("port \(String(port))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if status.peers.isEmpty {
                Text("No peers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(status.peers, id: \.publicKey) { peer in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: peer.freshness.systemImageName)
                            .foregroundStyle(peer.freshness.color)
                        Text(peer.allowedIPs.joined(separator: ", "))
                            .font(.caption.monospaced())
                        Spacer()
                        if let endpoint = peer.endpoint {
                            Text(endpoint)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Group {
                        if let handshake = peer.latestHandshake {
                            Text("Handshake: \(handshake)")
                        } else {
                            Text("No handshake yet")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if let transfer = peer.transfer {
                        Text(transfer)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 2)
            }
        }
    }
}

struct ContainerStatusList: View {
    let containers: [ContainerStatus]
    /// Show a friendlier, title-cased container name
    var prettify = false
    /// When set, each row expands into start/stop/restart buttons
    var onAction: ((ContainerStatus, CommandCatalog.Containers.Action) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(containers, id: \.name) { container in
                ContainerControlRow(container: container, prettify: prettify,
                                    onAction: onAction.map { handler in
                                        { handler(container, $0) }
                                    })
            }
        }
    }
}

struct ContainerControlRow: View {
    let container: ContainerStatus
    var prettify = false
    var onAction: ((CommandCatalog.Containers.Action) -> Void)?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard onAction != nil else { return }
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .disabled(onAction == nil)

            if expanded, let onAction {
                CompactActionGroup([
                    CompactAction("Start", systemImage: "play.fill") { onAction(.start) },
                    CompactAction("Restart", systemImage: "arrow.clockwise") { onAction(.restart) },
                    CompactAction("Stop", systemImage: "stop.fill", role: .destructive) {
                        onAction(.stop)
                    }
                ])
                .padding(.bottom, 2)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 6) {
            Image(systemName: container.health.systemImageName)
                .foregroundStyle(container.health.color)
            Text(verbatim: prettify ? ContainerName.pretty(container.name) : container.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(container.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if onAction != nil {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
        }
        .contentShape(Rectangle())
    }
}

struct CollapsibleContainerList: View {
    let containers: [ContainerStatus]
    /// Forwarded to each row's start/stop/restart buttons when set
    var onAction: ((ContainerStatus, CommandCatalog.Containers.Action) -> Void)?
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ContainerStatusList(containers: containers, prettify: true, onAction: onAction)
        } label: {
            ContainerHealthSummary(containers: containers)
        }
    }
}

struct ContainerHealthSummary: View {
    let containers: [ContainerStatus]

    private var unhealthy: Int { containers.filter { $0.health != .ok }.count }

    var body: some View {
        if containers.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else if unhealthy == 0 {
            Label("All systems healthy!", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else {
            Label("\(unhealthy) need attention", systemImage: HealthLevel.warning.systemImageName)
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }
}

enum ContainerName {
    static func pretty(_ raw: String) -> String {
        var tokens = raw.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        if let last = tokens.last, Int(last) != nil { tokens.removeLast() }  // replica index
        tokens.removeAll { $0.isEmpty || $0 == "mailcow" || $0 == "mailcowdockerized" }
        let words = tokens.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? raw : words.joined(separator: " ")
    }
}

struct BackupListView: View {
    let entries: [BackupEntry]

    var body: some View {
        if entries.isEmpty {
            Text("No backups")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries, id: \.name) { entry in
                    HStack {
                        Text(entry.displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(entry.sizeText) · \(entry.dateText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

/// The whole log, following its newest line
struct OperationLogView: View {
    let log: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(log)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Color.clear.frame(height: 1).id(Self.end)
                }
            }
            .frame(maxHeight: .infinity)
            .onAppear { proxy.scrollTo(Self.end, anchor: .bottom) }
            .onChange(of: log) { proxy.scrollTo(Self.end, anchor: .bottom) }
        }
    }

    private static let end = "operation-log-end"
}

struct LongOperationSheet: View {
    @ObservedObject var operation: LongOperationState
    var downloadBackup: ((String) async throws -> Data)?
    let onDismiss: () -> Void

    @State private var isPreparingShare = false
    @State private var shareError: String?
    @State private var shareFileURL: URL?
    @State private var showingShareSheet = false
    @State private var updatingDNS = false

    private var asksForDNS: Binding<Bool> {
        Binding(get: { operation.isFinished && operation.dnsUpdate != nil && !updatingDNS },
                set: { if !$0, !updatingDNS { operation.dnsUpdate = nil } })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    if !operation.isFinished || updatingDNS {
                        ProgressView()
                    } else if operation.errorMessage != nil {
                        Image(systemName: HealthLevel.critical.systemImageName)
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: HealthLevel.ok.systemImageName)
                            .foregroundStyle(.green)
                    }
                    Text(operation.errorMessage ?? operation.progressText)
                        .font(.callout)
                }

                if let notice = operation.notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                shareRow

                if !operation.log.isEmpty {
                    OperationLogView(log: operation.log)
                }

                Spacer(minLength: 0)

                #if os(macOS)
                HStack {
                    Spacer()
                    Button(operation.isFinished ? "Close" : "Minimize", action: onDismiss)
                        .keyboardShortcut(.defaultAction)
                }
                #endif
            }
            .padding()
            .navigationTitle(operation.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(operation.isFinished ? "Close" : "Minimize", action: onDismiss)
                }
            }
            #endif
            .shareSheet(isPresented: $showingShareSheet,
                        items: shareFileURL.map { [$0] } ?? [])
            .alert("The DNS records need updating", isPresented: asksForDNS, presenting: operation.dnsUpdate) { update in
                Button("Update") { updateDNS(update) }
                Button("Later", role: .cancel) { operation.dnsUpdate = nil }
            } message: { update in
                Text(verbatim: update.summary)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    @ViewBuilder
    private var shareRow: some View {
        if operation.isFinished, operation.errorMessage == nil,
           let path = operation.shareableBackupPath, let downloadBackup {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    prepareShare(path: path, download: downloadBackup)
                } label: {
                    if isPreparingShare {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Downloading…")
                        }
                    } else {
                        Label("Share backup…", systemImage: "square.and.arrow.up")
                    }
                }
                .secondaryActionButtonStyle()
                .disabled(isPreparingShare)
                if let shareError {
                    Label(shareError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func updateDNS(_ update: ServiceDNSPublisher.Update) {
        updatingDNS = true
        Task { @MainActor in
            let lines = await update.apply()
            operation.dnsUpdate = nil
            updatingDNS = false
            if !lines.isEmpty { operation.notice = lines.joined(separator: "\n") }
        }
    }

    private func prepareShare(path: String, download: @escaping (String) async throws -> Data) {
        isPreparingShare = true
        shareError = nil
        Task { @MainActor in
            defer { isPreparingShare = false }
            do {
                shareFileURL = try await BackupSharing.stage(path: path, download: download)
                showingShareSheet = true
            } catch {
                shareError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

enum BackupSharing {
    static func stage(path: String,
                      download: @escaping (String) async throws -> Data) async throws -> URL {
        let data = try await download(path)
        let name = RemotePath.name(of: path)
        return try await Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        }.value
    }
}

/// Passphrase prompt for the encrypted Vaultwarden backup
struct PassphraseSheet: View {
    @State private var passphrase = ""
    @State private var confirmation = ""
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    private var canSubmit: Bool {
        passphrase.count >= 8 && passphrase == confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Encryption password", text: $passphrase)
                    SecureField("Repeat password", text: $confirmation)
                } header: {
                    InfoSectionHeader("Encryption password", note: "The passphrase is used only for this operation: it encrypts the archive (GPG, AES256) and is never stored. Without it the backup cannot be decrypted.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, minHeight: 260)
            #endif
            .navigationTitle("Backup Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Backup") { onConfirm(passphrase) }
                        .disabled(!canSubmit)
                }
            }
        }
    }
}
