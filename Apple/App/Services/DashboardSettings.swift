import Foundation
import ServerControl

enum DashboardSettingsKeys {
    static let vpsHost = "dashboard.vpsHost"
    static let sshPort = "dashboard.sshPort"
    static let sshUser = "dashboard.sshUser"
    static let homeWGAddress = "dashboard.homeWGAddress"
    static let wgInterface = "dashboard.wgInterface"
    static let mailcowPath = "dashboard.mailcowPath"
    static let vaultwardenContainer = "dashboard.vaultwardenContainer"
    static let vaultwardenDataPath = "dashboard.vaultwardenDataPath"
    static let mailcowBackupDir = "dashboard.mailcowBackupDir"
    static let vaultwardenBackupDir = "dashboard.vaultwardenBackupDir"
    static let backupRetention = "dashboard.backupRetention"
    static let quickTimeoutSeconds = "dashboard.quickTimeoutSeconds"
    static let restartTimeoutSeconds = "dashboard.restartTimeoutSeconds"
    static let mailcowRestartTimeoutSeconds = "dashboard.mailcowRestartTimeoutSeconds"
    static let longTimeoutSeconds = "dashboard.longTimeoutSeconds"
}

extension DashboardConfig {
    /// Reads the current settings; unset fields fall back to defaults
    static func fromUserDefaults(_ defaults: UserDefaults = .standard) -> DashboardConfig {
        var config = DashboardConfig.default
        func value(_ key: String) -> String? {
            defaults.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
        }
        config.vpsHost = value(DashboardSettingsKeys.vpsHost) ?? config.vpsHost
        if defaults.object(forKey: DashboardSettingsKeys.sshPort) != nil {
            config.sshPort = defaults.integer(forKey: DashboardSettingsKeys.sshPort)
        }
        config.sshUser = value(DashboardSettingsKeys.sshUser) ?? config.sshUser
        config.homeWGAddress = value(DashboardSettingsKeys.homeWGAddress) ?? config.homeWGAddress
        config.wgInterface = value(DashboardSettingsKeys.wgInterface) ?? config.wgInterface
        config.mailcowPath = value(DashboardSettingsKeys.mailcowPath) ?? config.mailcowPath
        config.vaultwardenContainer = value(DashboardSettingsKeys.vaultwardenContainer) ?? config.vaultwardenContainer
        config.vaultwardenDataPath = value(DashboardSettingsKeys.vaultwardenDataPath) ?? config.vaultwardenDataPath
        config.mailcowBackupDir = value(DashboardSettingsKeys.mailcowBackupDir) ?? config.mailcowBackupDir
        config.vaultwardenBackupDir = value(DashboardSettingsKeys.vaultwardenBackupDir) ?? config.vaultwardenBackupDir
        func intValue(_ key: String) -> Int? {
            guard defaults.object(forKey: key) != nil else { return nil }
            let stored = defaults.integer(forKey: key)
            return stored > 0 ? stored : nil
        }
        config.backupRetention = intValue(DashboardSettingsKeys.backupRetention) ?? config.backupRetention
        config.quickTimeoutSeconds = intValue(DashboardSettingsKeys.quickTimeoutSeconds) ?? config.quickTimeoutSeconds
        config.restartTimeoutSeconds = intValue(DashboardSettingsKeys.restartTimeoutSeconds) ?? config.restartTimeoutSeconds
        config.mailcowRestartTimeoutSeconds = intValue(DashboardSettingsKeys.mailcowRestartTimeoutSeconds) ?? config.mailcowRestartTimeoutSeconds
        config.longTimeoutSeconds = intValue(DashboardSettingsKeys.longTimeoutSeconds) ?? config.longTimeoutSeconds
        return config
    }
}
