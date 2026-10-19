import ServerControl
import SwiftUI

struct BackupDestinationView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var draft = BackupDestinationSettings()
    @State private var secret = ""
    @State private var fleet: [Deployment] = []
    @State private var targetID: UUID?

    private var candidates: [Deployment] {
        fleet.filter { $0.id != viewModel.deployment.id }
    }

    var body: some View {
        Form {
            kindSection
            switch draft.kind {
            case .none: EmptyView()
            case .ssh: sshSection
            case .s3: bucketSection
            }
            if draft.kind != .none { commonSection }
            statusSection
            saveSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Backup destination")
        .raisedNavigationTitle()
        .task {
            fleet = (try? FileDeploymentStore().load()) ?? []
            await viewModel.loadBackupDestination()
            draft = viewModel.backupDestination.settings
            targetID = candidates.first {
                $0.entry.host == draft.host && draft.kind == .ssh
            }?.id
        }
    }

    // MARK: - Where

    @ViewBuilder private var kindSection: some View {
        Section {
            WrappingPicker("Copies go to", selection: $draft.kind) {
                Text("Nowhere — kept on this server").tag(BackupDestinationSettings.Kind.none)
                Text("Another of your servers").tag(BackupDestinationSettings.Kind.ssh)
                Text("An S3 bucket").tag(BackupDestinationSettings.Kind.s3)
            }
        } header: {
            InfoSectionHeader("Backup destination", note: "A backup that lives on the machine it was taken from does not survive that machine — which is the one failure a backup is for. Copies are sent right after each archive is made, by the same schedule that makes them. A copy that fails never fails the backup; it is recorded here instead.")
        }
    }

    @ViewBuilder private var sshSection: some View {
        if !candidates.isEmpty {
            Section {
                ForEach(candidates) { server in
                    Button {
                        targetID = server.id
                        draft.host = server.entry.host
                        draft.port = server.entry.port
                        draft.user = server.entry.user
                        if draft.path.isEmpty { draft.path = "/srv/backups" }
                    } label: {
                        LabeledContent {
                            if targetID == server.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: server.name)
                                Text(verbatim: server.entry.host)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                InfoSectionHeader("Your servers", note: "Picking one fills in its address and account. The key the copies travel with is made by THIS server; the button below puts its public half on the one you picked, using the access this app already has to it.")
            }
        }

        Section {
            field("Host", prompt: "backup.example.com", text: $draft.host)
            LabeledContent("Port") {
                TextField("Port", value: $draft.port, format: .number,
                          prompt: Text(verbatim: "22").foregroundStyle(.secondary))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
            }
            field("User", prompt: "backups", text: $draft.user)
            field("Folder", prompt: "/srv/backups", text: $draft.path)
        } header: {
            Text("Where to copy to")
        } footer: {
            Text("This server's own name is added to the folder, so several servers can share one destination without landing on each other.")
        }

        if !viewModel.backupDestination.publicKey.isEmpty {
            Section {
                Text(verbatim: viewModel.backupDestination.publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if let target = candidates.first(where: { $0.id == targetID }) {
                    Button {
                        Task { await viewModel.authorizeBackupKey(on: target) }
                    } label: {
                        Label("Authorize this key on \(target.name)", systemImage: "key")
                    }
                    .rowActionButtonStyle()
                    .disabled(viewModel.backupDestinationBusy)
                }
            } header: {
                InfoSectionHeader("This server's shipping key", note: "Made by the server itself and never leaves it — only this public half travels. On a destination this app does not manage, add the line to that account's authorized_keys by hand.")
            }
        }
    }

    @ViewBuilder private var bucketSection: some View {
        Section {
            field("Bucket", prompt: "my-backups", text: $draft.bucket)
            field("Endpoint", prompt: "s3.eu-central-1.amazonaws.com", text: $draft.host)
            field("Prefix", prompt: "servers", text: $draft.path)
            SecureTechnicalField(title: "Access key : secret", text: $secret)
        } header: {
            InfoSectionHeader("Bucket", note: "Any S3-compatible storage. The credentials are written to a root-only file on the server and never read back — leave the field empty to keep what is already stored. The server needs rclone installed; the check below says so if it is missing.")
        }
    }

    @ViewBuilder private var commonSection: some View {
        Section {
            Stepper(value: $draft.keep, in: 0...90) {
                HStack {
                    Text("Keep on the destination")
                    Spacer()
                    Text(verbatim: draft.keep == 0 ? UIL10n.string("Everything") : "\(draft.keep)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } footer: {
            Text("How many copies the destination keeps. This is a different number from what this server keeps — the point of the far side is usually that it has more room.")
        }
    }

    // MARK: - What it did

    @ViewBuilder private var statusSection: some View {
        Section {
            if let result = viewModel.backupDestinationCheck {
                Label(result.succeeded
                        ? UIL10n.string("The destination answered.")
                        : (result.detail.isEmpty
                            ? UIL10n.string("The destination did not answer.") : result.detail),
                      systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(result.succeeded ? Color.green : Color.orange)
                    .font(.callout)
            }
            if let last = viewModel.backupDestination.lastShipment {
                LabeledContent("Last copy") {
                    Text(last, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                if !viewModel.backupDestination.lastShipmentSucceeded {
                    Text(verbatim: viewModel.backupDestination.lastError.isEmpty
                         ? UIL10n.string("The last copy failed.")
                         : viewModel.backupDestination.lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else if draft.kind != .none {
                Text("Nothing has been copied yet.")
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.checkBackupDestination() }
            } label: {
                HStack {
                    Label("Check the destination", systemImage: "paperplane")
                    if viewModel.backupDestinationBusy {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .rowActionButtonStyle()
            .disabled(draft.kind == .none || viewModel.backupDestinationBusy)
        } header: {
            InfoSectionHeader("Checking", note: "Sends one small file the same way an archive is sent. A destination that has never been checked is one nobody knows is working — and an unattended copy that silently fails is what this screen exists to make impossible.")
        }
    }

    @ViewBuilder private var saveSection: some View {
        Section {
            Button {
                Task {
                    await viewModel.saveBackupDestination(draft, secret: secret.isEmpty ? nil : secret)
                    secret = ""
                    draft = viewModel.backupDestination.settings
                }
            } label: {
                Text("Save destination")
            }
            .rowActionButtonStyle()
            .disabled(viewModel.backupDestinationBusy || !isComplete)
        } footer: {
            if let error = viewModel.backupDestinationError {
                Text(verbatim: error).foregroundStyle(.red)
            }
        }
    }

    private var isComplete: Bool {
        draft.kind == .none || draft.isConfigured
    }

    private func field(_ title: LocalizedStringKey, prompt: LocalizedStringKey,
                       text: Binding<String>) -> some View {
        LabeledContent {
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(.secondary))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        } label: {
            Text(title)
        }
    }
}
