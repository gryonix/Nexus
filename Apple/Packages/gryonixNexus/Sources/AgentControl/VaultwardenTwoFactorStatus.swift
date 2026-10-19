import AgentClient

/// How many Vaultwarden accounts have no two-factor login
public struct VaultwardenTwoFactorStatus: Equatable, Sendable {
    public let users: Int
    public let usersWithoutTwoFactor: Int

    public init(users: Int, usersWithoutTwoFactor: Int) {
        self.users = users
        self.usersWithoutTwoFactor = usersWithoutTwoFactor
    }

    public var needsAttention: Bool { usersWithoutTwoFactor > 0 }

    /// Nil when the agent could not read the database
    public init?(_ answer: Gryonixnexusd_V1_VaultwardenTwoFactor) {
        guard answer.readable else { return nil }
        self.init(users: Int(answer.users), usersWithoutTwoFactor: Int(answer.usersWithoutTwoFactor))
    }
}
