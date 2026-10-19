import Foundation
import MailRecipe
import ServerControl

struct DeploymentTransfer: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var deployment: Deployment
    var sshIdentitySeed: Data?
    var sshTransferID: String?
    var dashboardPassword: String?
    /// WireGuardKeySlot.rawValue ("vps"/"home") → 32-byte tunnel seed
    var wireGuardSeeds: [String: Data]
    var hostKeyPins: [String: String]
    var reports: [StoredInstallReport]
    var configuration: ConfiguratorDraft?
    /// Scenario B: the home machine's address on the local network
    var homeLANAddress: String?
    var accessCredentials: [String: AccessCredential]?
    var installUsers: [String: String]?
    /// Machine name → the management password of THAT machine
    var dashboardPasswords: [String: String]?

    enum TransferError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return UIL10n.string("This file was exported by a newer version of the app. Update the app and try again.")
            }
        }
    }
}

/// Builds, encodes, decodes and applies a `DeploymentTransfer`
enum DeploymentTransferService {
    /// File extension of an exported server bundle
    static let fileExtension = "gryonixserver"

    static func fileName(for deployment: Deployment) -> String {
        let base = deployment.domain.isEmpty ? deployment.name : deployment.domain
        let safe = base.replacingOccurrences(of: "/", with: "-")
        return "\(safe.isEmpty ? "server" : safe).\(fileExtension)"
    }

    static func export(_ deployment: Deployment,
                       transferKey: (seed: Data, id: String)? = nil,
                       keychain: KeychainStore = KeychainStore()) -> DeploymentTransfer {
        let id = deployment.id
        let sshSeed = transferKey?.seed
            ?? (try? KeychainSSHIdentityStore(deploymentID: id, keychain: keychain).load())?.privateKeySeed
        let passwordStore = DashboardPasswordStore(deploymentID: id, keychain: keychain)
        var passwords: [String: String] = [:]
        for node in deployment.nodes {
            if let stored = passwordStore.load(for: node.sshHost) {
                passwords[InstallAddressStore.machineName(node.sshHost)] = stored
            }
        }
        let password = passwords[InstallAddressStore.machineName(.vps)]

        var seeds: [String: Data] = [:]
        for (slot, seed) in KeychainWireGuardKeyProvider(deploymentID: id, keychain: keychain).storedSeeds() {
            seeds[slot.rawValue] = seed
        }

        let pinStore = HostKeyPinStore(deploymentID: id, keychain: keychain)
        var pins: [String: String] = [:]
        for node in deployment.nodes {
            if let pin = pinStore.pin(for: node.sshHost), pin != HostKeyPinAccounts.unreadable {
                pins[InstallAddressStore.machineName(node.sshHost)] = pin
            }
        }

        let reports = DeploymentReportStore(deploymentID: id, keychain: keychain).load()
        let overrides = AccessCredentialStore(deploymentID: id, keychain: keychain).load()

        let configuration = ConfiguratorStore.shared.configForReinstall(deploymentID: id)
        let lanAddress = InstallAddressStore.homeAddress(deploymentID: id)
        var installUsers: [String: String] = [:]
        for node in deployment.nodes {
            if let user = InstallAddressStore.installUser(deploymentID: id, host: node.sshHost) {
                installUsers[InstallAddressStore.machineName(node.sshHost)] = user
            }
        }

        return DeploymentTransfer(deployment: deployment,
                                  sshIdentitySeed: sshSeed,
                                  sshTransferID: transferKey?.id,
                                  dashboardPassword: password,
                                  wireGuardSeeds: seeds,
                                  hostKeyPins: pins,
                                  reports: reports,
                                  configuration: configuration,
                                  homeLANAddress: lanAddress.isEmpty ? nil : lanAddress,
                                  accessCredentials: overrides.isEmpty ? nil : overrides,
                                  installUsers: installUsers.isEmpty ? nil : installUsers,
                                  dashboardPasswords: passwords.isEmpty ? nil : passwords)
    }

    static func encode(_ transfer: DeploymentTransfer) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(transfer)
    }

    static func decode(_ data: Data) throws -> DeploymentTransfer {
        let transfer = try JSONDecoder().decode(DeploymentTransfer.self, from: data)
        guard transfer.version <= DeploymentTransfer.currentVersion else {
            throw DeploymentTransfer.TransferError.unsupportedVersion(transfer.version)
        }
        return transfer
    }

    @discardableResult
    static func apply(_ transfer: DeploymentTransfer,
                      store: any DeploymentStore,
                      keychain: KeychainStore = KeychainStore()) throws -> Deployment {
        let deployment = transfer.deployment
        let id = deployment.id

        if let seed = transfer.sshIdentitySeed {
            try? KeychainSSHIdentityStore(deploymentID: id, keychain: keychain)
                .save(AppSSHIdentity(privateKeySeed: seed))
            if let transferID = transfer.sshTransferID {
                PendingTransferStore(deploymentID: id, keychain: keychain).save(transferID)
            }
        }
        let passwordStore = DashboardPasswordStore(deploymentID: id, keychain: keychain)
        if let perMachine = transfer.dashboardPasswords, !perMachine.isEmpty {
            for (name, password) in perMachine {
                guard let host = InstallAddressStore.machine(named: name) else { continue }
                try? passwordStore.save(password, for: host)
            }
        } else if let password = transfer.dashboardPassword {
            for node in deployment.nodes {
                try? passwordStore.save(password, for: node.sshHost)
            }
        }

        var seeds: [WireGuardKeySlot: Data] = [:]
        for (raw, seed) in transfer.wireGuardSeeds {
            if let slot = WireGuardKeySlot(rawValue: raw) { seeds[slot] = seed }
        }
        KeychainWireGuardKeyProvider(deploymentID: id, keychain: keychain).restore(seeds: seeds)

        let pinStore = HostKeyPinStore(deploymentID: id, keychain: keychain)
        for node in deployment.nodes {
            if let pin = transfer.hostKeyPins[InstallAddressStore.machineName(node.sshHost)] {
                pinStore.store(pin, for: node.sshHost)
            }
        }

        let reportStore = DeploymentReportStore(deploymentID: id, keychain: keychain)
        for report in transfer.reports { reportStore.save(host: report.host, text: report.text) }

        if let overrides = transfer.accessCredentials, !overrides.isEmpty {
            AccessCredentialStore(deploymentID: id, keychain: keychain).save(overrides)
        }

        if var configuration = transfer.configuration {
            configuration.deploymentID = id
            ConfiguratorStore.shared.saveDeploymentConfig(configuration)
        }
        if let lan = transfer.homeLANAddress, !lan.isEmpty {
            InstallAddressStore.save(homeAddress: lan, deploymentID: id)
        }
        for (name, user) in transfer.installUsers ?? [:] {
            guard let host = InstallAddressStore.machine(named: name) else { continue }
            InstallAddressStore.save(installUser: user, deploymentID: id, host: host)
        }

        try store.upsert(deployment)
        return deployment
    }
}
