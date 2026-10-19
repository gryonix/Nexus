import ServerControl
import ServiceCatalog
import SwiftUI

struct BackupConfirmSheet: View {
    private static let largeBackupBytes: UInt64 = 10 * 1024 * 1024 * 1024

    let serviceName: String
    let encryptsByDefault: Bool
    let loadEstimate: () async throws -> BackupEstimate?
    let onCancel: () -> Void
    let onConfirm: (_ encrypt: Bool, _ passphrase: String?) -> Void

    @State private var estimate: BackupEstimate?
    @State private var estimateFailed: String?
    @State private var loading = true
    @State private var encrypt: Bool?
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var encrypting: Bool { encrypt ?? encryptsByDefault }

    private var doesNotFit: Bool {
        guard let estimate else { return false }
        return !estimate.fitsOnDisk
    }

    private var isLarge: Bool {
        guard let estimate else { return false }
        return estimate.dataBytes >= Self.largeBackupBytes
    }

    private var passphraseIsUsable: Bool {
        passphrase.isEmpty || (passphrase.count >= 8 && passphrase == confirmation)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loading {
                        HStack {
                            Text("Checking the size on the server…")
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    } else if let estimate {
                        LabeledContent("Data to back up", value: Self.format(estimate.dataBytes))
                        LabeledContent("Free on the server", value: Self.format(estimate.freeBytes))
                    } else {
                        Text("This server cannot estimate the size. Re-run the installation to update its scripts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let estimateFailed {
                        Label(estimateFailed, systemImage: HealthLevel.critical.systemImageName)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(serviceName)
                } footer: {
                    if doesNotFit {
                        Text("The backup may not fit: it is larger than the free space on the server. A run that fills the disk takes the running services down with it.")
                    } else if isLarge {
                        Text("This is a large backup. It can take a long time and will use as much disk space again while it runs.")
                    }
                }
                Section {
                    Toggle("Encrypt the backup",
                           isOn: Binding(get: { encrypting }, set: { encrypt = $0 }))
                    if encrypting {
                        SecureField("Encryption password", text: $passphrase)
                        SecureField("Repeat password", text: $confirmation)
                    }
                } footer: {
                    if encrypting {
                        Text("Leave the password empty to use the one saved for scheduled backups. A password typed here is used only for this backup and is never stored — without it the archive cannot be decrypted.")
                    } else {
                        Text("The archive is written unencrypted. Encrypting a large library costs hours of processor time on a small server, which is why it is off here by default.")
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, minHeight: 340)
            #endif
            .navigationTitle("Back Up")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(doesNotFit ? "Back Up Anyway" : "Back Up",
                           role: doesNotFit ? .destructive : nil) {
                        onConfirm(encrypting, passphrase.isEmpty ? nil : passphrase)
                    }
                    .disabled(loading || !passphraseIsUsable)
                }
            }
            .task {
                defer { loading = false }
                do {
                    estimate = try await loadEstimate()
                } catch {
                    estimateFailed = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    private static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary)
    }
}
