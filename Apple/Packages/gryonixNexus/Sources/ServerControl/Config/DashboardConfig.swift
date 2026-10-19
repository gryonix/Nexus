import Foundation

public struct DashboardConfig: Sendable, Hashable, Codable {
    // Connection
    public var vpsHost: String
    public var sshPort: Int
    /// Same login on both machines; also the sudoers subject
    public var sshUser: String
    public var homeWGAddress: String
    public var wgInterface: String

    public var mailcowPath: String
    public var vaultwardenContainer: String
    public var vaultwardenDataPath: String
    public var mailcowBackupDir: String
    public var vaultwardenBackupDir: String
    public var backupRetention: Int

    // Timeouts, seconds
    public var quickTimeoutSeconds: Int
    public var restartTimeoutSeconds: Int
    public var mailcowRestartTimeoutSeconds: Int
    /// Mailcow update and backups can run up to ten minutes
    public var longTimeoutSeconds: Int

    public init(
        vpsHost: String = "",
        sshPort: Int = 22,
        sshUser: String = "",
        homeWGAddress: String = "10.8.0.2",
        wgInterface: String = "wg0",
        mailcowPath: String = "/opt/mailcow-dockerized",
        vaultwardenContainer: String = "vaultwarden",
        vaultwardenDataPath: String = "/opt/vaultwarden/data",
        mailcowBackupDir: String = "/opt/backups/mailcow",
        vaultwardenBackupDir: String = "/opt/backups/vaultwarden",
        backupRetention: Int = 7,
        quickTimeoutSeconds: Int = 15,
        restartTimeoutSeconds: Int = 60,
        mailcowRestartTimeoutSeconds: Int = 120,
        longTimeoutSeconds: Int = 600
    ) {
        self.vpsHost = vpsHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.homeWGAddress = homeWGAddress
        self.wgInterface = wgInterface
        self.mailcowPath = mailcowPath
        self.vaultwardenContainer = vaultwardenContainer
        self.vaultwardenDataPath = vaultwardenDataPath
        self.mailcowBackupDir = mailcowBackupDir
        self.vaultwardenBackupDir = vaultwardenBackupDir
        self.backupRetention = backupRetention
        self.quickTimeoutSeconds = quickTimeoutSeconds
        self.restartTimeoutSeconds = restartTimeoutSeconds
        self.mailcowRestartTimeoutSeconds = mailcowRestartTimeoutSeconds
        self.longTimeoutSeconds = longTimeoutSeconds
    }

    public static let `default` = DashboardConfig()

    public var quickTimeout: Duration { .seconds(quickTimeoutSeconds) }
    public var restartTimeout: Duration { .seconds(restartTimeoutSeconds) }
    public var mailcowRestartTimeout: Duration { .seconds(mailcowRestartTimeoutSeconds) }
    public var longTimeout: Duration { .seconds(longTimeoutSeconds) }

    /// Minimum needed to open a connection
    public var isConnectable: Bool {
        !vpsHost.isEmpty && !sshUser.isEmpty && (1...65535).contains(sshPort)
    }
}
