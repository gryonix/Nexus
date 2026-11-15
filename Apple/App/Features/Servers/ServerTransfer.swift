import ServerControl
import SwiftUI

/// Passphrases and the replace question around server files
@MainActor
final class ServerTransferModel: ObservableObject {
    enum Prompt: Identifiable {
        case export([Deployment])
        /// Groups and their servers, as one file
        case exportGroups([String])
        case unlock(Data)

        var id: String {
            switch self {
            case .export(let deployments): return "export-" + deployments.map(\.id.uuidString).joined()
            case .exportGroups(let groups): return "groups-" + groups.joined(separator: "\n")
            case .unlock(let data): return "unlock-\(data.hashValue)"
            }
        }

        var isExport: Bool {
            switch self {
            case .export, .exportGroups: return true
            case .unlock: return false
            }
        }
    }

    @Published var prompt: Prompt?
    @Published var promptError: String?
    @Published var replacing: DeploymentTransfer?
    private var queuedReplacements: [DeploymentTransfer] = []

    static let minimumPassphrase = 8

    func askToExport(_ deployments: [Deployment]) {
        promptError = nil
        prompt = .export(deployments)
    }

    func askToExport(groups: [String]) {
        promptError = nil
        prompt = .exportGroups(groups)
    }

    /// A picked file: sealed files ask for their passphrase first
    func received(_ data: Data, into list: ServerListViewModel) {
        if TransferSeal.isSealed(data) {
            promptError = nil
            prompt = .unlock(data)
            return
        }
        decodeAndOffer(data, into: list)
    }

    func unlock(_ data: Data, passphrase: String, into list: ServerListViewModel) {
        do {
            let plain = try TransferSeal.open(data, passphrase: passphrase)
            prompt = nil
            decodeAndOffer(plain, into: list)
        } catch TransferSeal.Failure.wrongPassphrase {
            promptError = UIL10n.string("Wrong passphrase.")
        } catch {
            prompt = nil
            list.errorMessage = UIL10n.string("Failed to import the server: %@", error.localizedDescription)
        }
    }

    func confirmReplace(into list: ServerListViewModel) {
        guard let transfer = replacing else { return }
        replacing = nil
        list.apply(transfer)
        warnIfCannotConnect(transfer, list: list)
        askNextReplacement()
    }

    func skipReplace() {
        replacing = nil
        askNextReplacement()
    }

    /// Servers from a QR transfer; returns the names taken in
    func offer(_ transfers: [DeploymentTransfer], into list: ServerListViewModel) -> [String] {
        for transfer in transfers {
            if list.deployments.contains(where: { $0.id == transfer.deployment.id }) {
                queuedReplacements.append(transfer)
            } else {
                list.apply(transfer)
                warnIfCannotConnect(transfer, list: list)
            }
        }
        return transfers.map(\.deployment.name)
    }

    func askNextReplacement() {
        guard replacing == nil, !queuedReplacements.isEmpty else { return }
        let next = queuedReplacements.removeFirst()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            replacing = next
        }
    }

    private func warnIfCannotConnect(_ transfer: DeploymentTransfer, list: ServerListViewModel) {
        let hasPassword = !(transfer.dashboardPasswords ?? [:]).isEmpty || transfer.dashboardPassword != nil
        guard transfer.sshIdentitySeed == nil, !hasPassword, list.errorMessage == nil else { return }
        list.errorMessage = UIL10n.string(
            "The file holds no key or password for “%@”, so the app cannot connect to it. Export the server again from a device that can connect.",
            transfer.deployment.name)
    }

    private func decodeAndOffer(_ data: Data, into list: ServerListViewModel) {
        if ServerGroupBundle.isBundle(data) {
            offerGroups(data, into: list)
            return
        }
        do {
            let transfer = try DeploymentTransferService.decode(data)
            if list.deployments.contains(where: { $0.id == transfer.deployment.id }) {
                replacing = transfer
            } else {
                list.apply(transfer)
                warnIfCannotConnect(transfer, list: list)
            }
        } catch {
            list.errorMessage = UIL10n.string("Failed to import the server: %@", error.localizedDescription)
        }
    }
}

extension ServerTransferModel {
    /// A group file: its order first, then its servers
    func offerGroups(_ data: Data, into list: ServerListViewModel) {
        do {
            let bundle = try ServerGroupBundle.decode(data)
            list.adoptGroupOrder(bundle.groups)
            _ = offer(bundle.servers, into: list)
            askNextReplacement()
        } catch {
            list.errorMessage = UIL10n.string("Failed to import the server: %@", error.localizedDescription)
        }
    }
}

/// Asks the passphrase that seals or opens a file
struct TransferPassphraseSheet: View {
    let prompt: ServerTransferModel.Prompt
    let error: String?
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var passphrase = ""
    @State private var repeated = ""

    private var isExport: Bool { prompt.isExport }

    private var canSubmit: Bool {
        isExport
            ? passphrase.count >= ServerTransferModel.minimumPassphrase && passphrase == repeated
            : !passphrase.isEmpty
    }

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .accessibilityIdentifier("transfer.passphrase")
                    if isExport {
                        SecureField("Repeat the passphrase", text: $repeated)
                            .accessibilityIdentifier("transfer.repeat")
                    }
                } footer: {
                    footer
                }
            }
            .screenTitle(isExport ? "Protect the file" : "Open the file")
            .raisedNavigationTitle()
            .toolbar { toolbar }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 280)
            #endif
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isExport
                 ? "The file is encrypted with this passphrase. Tell it to the other device separately — at least 8 characters."
                 : "Enter the passphrase this file was exported with.")
            if let error {
                Text(verbatim: error).foregroundStyle(.red)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isExport ? "Export" : "Open") { onSubmit(passphrase) }
                .disabled(!canSubmit)
                .accessibilityIdentifier("transfer.submit")
        }
    }
}
