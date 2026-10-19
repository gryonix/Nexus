import ServerControl
import ServiceCatalog
import SwiftUI

/// Builds a new array from free disks
struct StorageBuildView: View {
    @ObservedObject var model: StorageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var choice = StorageChoice()

    private var candidates: [ServerDisk] { model.hardware.map(RaidPlan.candidates(in:)) ?? [] }

    private var plan: RaidPlan? {
        guard let hardware = model.hardware else { return nil }
        let disks = candidates.filter { choice.raidDisks.contains($0.path) }
        return RaidPlan.storage(level: choice.raidLevel, disks: disks, kind: choice.raidKind, in: hardware)
    }

    private var step: StorageStep? {
        guard let plan, plan.isValid, StoragePreparation.confirms(choice.confirmation) else { return nil }
        return .raid(plan, title: UIL10n.string("Building the RAID array…"))
    }

    var body: some View {
        Form {
            Section {
                RaidChoiceRows(choice: $choice, candidates: candidates, plan: plan)
            } header: {
                Text("RAID array")
            } footer: {
                if let mount = plan?.mountPoint {
                    Text("The array is mounted at \(mount) — use it for photos, files and media.")
                }
            }
            StorageSignInSection(model: model)
            StorageRunSection(model: model, title: "Build an array", step: step, destructive: true) { dismiss() }
        }
        .navigationTitle("Build an array")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .task { await model.loadStoredSecret() }
    }
}

/// Who runs disk changes: the server's own account or root
struct StorageSignInSection: View {
    @ObservedObject var model: StorageViewModel

    var body: some View {
        Section {
            Toggle(isOn: $model.usesServerAccount) {
                Text("Use the server's account (\(model.serverAccount))")
            }
        } header: {
            Text("Sign in")
        } footer: {
            if model.usesServerAccount && model.deployment.usesAgent {
                Text("The agent on the server does the disk work as root.")
            } else {
                Text(model.usesServerAccount
                     ? "Runs over the connection this server was added with. An account other than root needs sudo without a password."
                     : "Repairs change disks, so they run as root — the same sign-in the installation used.")
            }
        }
        if !model.usesServerAccount {
            Section {
                TechnicalField(title: "Install user", prompt: "root", text: $model.username)
            }
            SSHSecretSection(draft: $model.secret, appKeyIsInstalled: true,
                             appKeyFooter: "Uses the key granted for the installation.")
        }
    }
}

/// The run button with its progress and failure
struct StorageRunSection: View {
    @ObservedObject var model: StorageViewModel
    let title: LocalizedStringKey
    let step: StorageStep?
    var destructive = false
    let onDone: () -> Void

    var body: some View {
        Section {
            Button(role: destructive ? .destructive : nil) {
                guard let step else { return }
                Task {
                    await model.run(step)
                    if model.stepFailure == nil { onDone() }
                }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    if model.runningStep != nil { ProgressView().controlSize(.small) }
                }
            }
            .disabled(step == nil || model.runningStep != nil)
        } footer: {
            if let failure = model.stepFailure { Text(verbatim: failure).foregroundStyle(.red) }
        }
    }
}
