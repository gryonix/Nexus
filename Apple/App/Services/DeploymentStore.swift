import Foundation
import ServerControl
import ServiceCatalog
import VPNTunnel

enum LegacyDashboardMigrator {
    private static let legacyIdentityAccount = "dashboard-ssh-identity-seed"
    private static let legacyPinAccounts: [(String, SSHHostID)] = [
        ("dashboard-hostkey-vps", .vps),
        ("dashboard-hostkey-home", .home)
    ]

    static func migrateIfNeeded(store: any DeploymentStore,
                                defaults: UserDefaults = .standard,
                                keychain: KeychainStore = KeychainStore()) -> Deployment? {
        guard let host = defaults.string(forKey: DashboardSettingsKeys.vpsHost),
              !host.isEmpty else { return nil }

        let config = DashboardConfig.fromUserDefaults(defaults)
        let deployment = Deployment(
            name: UIL10n.string("My server"),
            topology: .vpsRelayWithHomeBackend,
            entry: HostEndpoint(host: config.vpsHost, port: config.sshPort, user: config.sshUser),
            homeWGAddress: config.homeWGAddress,
            wgInterface: config.wgInterface,
            // The single-server dashboard assumed the mailcow+vaultwarden pair.
            services: [.mailcow, .vaultwarden],
            serviceSettings: ServiceSettings(
                mailcowPath: config.mailcowPath,
                mailcowBackupDir: config.mailcowBackupDir,
                vaultwardenContainer: config.vaultwardenContainer,
                vaultwardenDataPath: config.vaultwardenDataPath,
                vaultwardenBackupDir: config.vaultwardenBackupDir,
                backupRetention: config.backupRetention
            ),
            timeouts: OperationTimeouts(
                quickSeconds: config.quickTimeoutSeconds,
                restartSeconds: config.restartTimeoutSeconds,
                serviceRestartSeconds: config.mailcowRestartTimeoutSeconds,
                longSeconds: config.longTimeoutSeconds
            )
        )

        do {
            try store.upsert(deployment)
        } catch {
            return nil
        }

        if let seed = try? keychain.data(for: legacyIdentityAccount) {
            try? KeychainSSHIdentityStore(deploymentID: deployment.id)
                .save(AppSSHIdentity(privateKeySeed: seed))
            try? keychain.delete(legacyIdentityAccount)
        }
        let pins = HostKeyPinStore(deploymentID: deployment.id)
        for (account, host) in legacyPinAccounts {
            if let pin = try? keychain.string(for: account) {
                pins.store(pin, for: host)
                try? keychain.delete(account)
            }
        }

        // Retire the global settings; per-deployment settings own them now.
        for key in [DashboardSettingsKeys.vpsHost, DashboardSettingsKeys.sshPort,
                    DashboardSettingsKeys.sshUser, DashboardSettingsKeys.homeWGAddress,
                    DashboardSettingsKeys.wgInterface, DashboardSettingsKeys.mailcowPath,
                    DashboardSettingsKeys.vaultwardenContainer, DashboardSettingsKeys.vaultwardenDataPath,
                    DashboardSettingsKeys.mailcowBackupDir, DashboardSettingsKeys.vaultwardenBackupDir,
                    DashboardSettingsKeys.backupRetention, DashboardSettingsKeys.quickTimeoutSeconds,
                    DashboardSettingsKeys.restartTimeoutSeconds, DashboardSettingsKeys.mailcowRestartTimeoutSeconds,
                    DashboardSettingsKeys.longTimeoutSeconds] {
            defaults.removeObject(forKey: key)
        }
        return deployment
    }
}

enum DeploymentEraser {
    /// Drops the deployment from the list store
    static func removeEntry(_ deployment: Deployment, store: any DeploymentStore) throws {
        try store.remove(id: deployment.id)
    }

    static func eraseSecrets(deploymentID id: UUID, nodeIDs: [UUID] = []) {
        try? KeychainSSHIdentityStore(deploymentID: id).delete()
        PendingTransferStore(deploymentID: id).clear()
        DashboardPasswordStore(deploymentID: id).delete(nodeIDs: nodeIDs)
        TerminalProfileStore(deploymentID: id).delete()
        InstallCredentialStore(deploymentID: id).deleteAll(nodeIDs: nodeIDs)
        HostKeyPinStore(deploymentID: id).resetAll(nodeIDs: nodeIDs)
        InstallJobStore().forgetAll(deployment: id)
        InstallAddressStore.forget(deploymentID: id, nodeIDs: nodeIDs)
        DashboardSessionFactory.invalidate(deploymentID: id)
        Task { @MainActor in
            DashboardTabSettings.shared.forget(deploymentID: id)
            EnergySettings.shared.forget(deploymentID: id)
        }
        KeychainWireGuardKeyProvider(deploymentID: id).deleteAll()
        DeploymentReportStore(deploymentID: id).delete()
        AccessCredentialStore(deploymentID: id).delete()
        ConfiguratorStore.shared.deleteDeploymentConfig(for: id)
        Task { @MainActor in await TunnelController.shared.removeProfiles(forServer: id) }
        FleetSnapshotStore().forgetServer(id: id)
        ServerAccessStore.forget(id)
    }
}
