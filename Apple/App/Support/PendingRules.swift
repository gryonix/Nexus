import ServerControl

/// When an edited setting waits in the bar
enum PendingRules {
    /// A valid, changed value waits unless work runs
    static func waits<Value: Equatable>(_ draft: Value?, saved: Value?, valid: Bool = true, busy: Bool = false) -> Bool {
        guard let draft else { return false }
        return draft != saved && valid && !busy
    }

    static func hostName(_ draft: String, saved: String) -> Bool {
        waits(draft, saved: saved, valid: HostNameRules.isValid(draft))
    }

    /// A typed passphrase waits even with an unchanged schedule
    static func backupSchedule(canSave: Bool, changed: Bool, passphrase: String) -> Bool {
        canSave && (changed || !passphrase.isEmpty)
    }
}
