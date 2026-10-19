import gryonixNexusCore

public struct DashboardAccessInput: Sendable, Hashable {
    public static let defaultUser = "server-user"

    public let sshUser: String
    public let createUser: Bool
    /// Full authorized_keys line, e.g
    public let appPublicKey: String
    public let mailcowPath: String
    public let vaultwardenContainer: String
    public let vaultwardenDataPath: String
    public let mailcowBackupDir: String
    public let vaultwardenBackupDir: String
    public let backupRetention: Int

    public init(
        sshUser: String,
        createUser: Bool = true,
        appPublicKey: String,
        mailcowPath: String = "/opt/mailcow-dockerized",
        vaultwardenContainer: String = "vaultwarden",
        vaultwardenDataPath: String = "/opt/vaultwarden/data",
        mailcowBackupDir: String = "/opt/backups/mailcow",
        vaultwardenBackupDir: String = "/opt/backups/vaultwarden",
        backupRetention: Int = 7
    ) {
        self.sshUser = sshUser
        self.createUser = createUser
        self.appPublicKey = appPublicKey
        self.mailcowPath = mailcowPath
        self.vaultwardenContainer = vaultwardenContainer
        self.vaultwardenDataPath = vaultwardenDataPath
        self.mailcowBackupDir = mailcowBackupDir
        self.vaultwardenBackupDir = vaultwardenBackupDir
        self.backupRetention = max(backupRetention, 1)
    }

    public var hasValidUser: Bool {
        guard let first = sshUser.first, first.isLowercase || first == "_" else { return false }
        return sshUser.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" || $0 == "-" }
            && sshUser.count <= 32
    }

    public var hasValidKey: Bool {
        appPublicKey.hasPrefix("ssh-ed25519 ") && !appPublicKey.contains("\n")
    }

    /// Docker container name: alphanumeric start, then [a-zA-Z0-9_.-]
    public var hasValidContainerName: Bool {
        guard let first = vaultwardenContainer.first, first.isLetter || first.isNumber else { return false }
        return vaultwardenContainer.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-"
        }
    }

    public var hasValidPaths: Bool {
        [mailcowPath, vaultwardenDataPath, mailcowBackupDir, vaultwardenBackupDir].allSatisfy { path in
            path.hasPrefix("/") && path.count > 1 && !path.hasSuffix("/") && path.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "/" || $0 == "_" || $0 == "." || $0 == "-"
            }
        }
    }
}
