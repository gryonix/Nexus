import AgentClient
import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

@available(macOS 15.0, *)
enum AccessVault {
    struct Fetched {
        var entries: [Gryonixnexusd_V1_VaultEntry] = []
        var reachedServer = false
        var sessionExpired = false
        var unidentified = false
        var failure: String?
    }

    static func fetch(deployment: Deployment) async -> Fetched {
        guard deployment.usesAgent else { return Fetched() }
        var result = Fetched()
        do {
            let session = try await AgentConnection.open(deployment: deployment)
            defer { Task { await session.runner.disconnect() } }
            let operations = AgentVaultOperations(client: session.client, deviceUID: DeviceIdentity.uid)
            result.entries = try await operations.snapshot().entries
            result.reachedServer = true
        } catch {
            result.sessionExpired = isSessionExpired(error)
            result.unidentified = isUnidentified(error)
            result.failure = result.sessionExpired || result.unidentified
                ? nil : message(for: error)
        }
        return result
    }

    /// Sends what this device changed
    @discardableResult
    static func push(_ entries: [Gryonixnexusd_V1_VaultEntry],
                     deployment: Deployment) async -> Bool {
        guard deployment.usesAgent, !entries.isEmpty else { return false }
        do {
            let session = try await AgentConnection.open(deployment: deployment)
            defer { Task { await session.runner.disconnect() } }
            let operations = AgentVaultOperations(client: session.client, deviceUID: DeviceIdentity.uid)
            _ = try await operations.save(entries)
            return true
        } catch {
            return false
        }
    }

    static func isSessionExpired(_ error: Error) -> Bool {
        text(of: error).contains("session_expired") || text(of: error).contains("device_not_paired")
    }

    static func isUnidentified(_ error: Error) -> Bool {
        text(of: error).contains("device_unidentified")
    }

    private static func text(of error: Error) -> String {
        if let agent = error as? AgentError, case .rpc(_, let message) = agent { return message }
        if let control = error as? ServerControlError,
           case .commandFailed(_, _, let stderr) = control { return stderr }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Building one schema entry out of one screen's account
enum AccessVaultEntry {
    /// Matches the editor's host|title identity on Android and Apple
    static func mailbox(host: String, address: String, password: String,
                        at date: Date, writer: String) -> Gryonixnexusd_V1_VaultEntry {
        let login = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = "Mailbox: \(login)"
        return make(id: "\(host)|\(title)", host: host, title: title, website: nil,
                    login: login, password: password, token: "", updatedAt: date, updatedBy: writer)
    }

    /// One model provider's API key, as a vault row
    static func modelProviderKey(host: String, provider: LLMProvider, key: String,
                                 at date: Date, writer: String) -> Gryonixnexusd_V1_VaultEntry {
        let title = "LiteLLM: \(provider.displayName)"
        var entry = make(id: "\(host)|\(title)", host: host, title: title,
                         website: provider.consoleURL, login: "",
                         password: "", token: key.trimmingCharacters(in: .whitespacesAndNewlines),
                         updatedAt: date, updatedBy: writer)
        entry.serviceSecret = provider.vaultSecretID
        return entry
    }

    /// The id both sides agree on
    static func make(id: String, host: String, title: String, website: String?,
                     login: String, password: String, token: String,
                     updatedAt: Date?, updatedBy: String) -> Gryonixnexusd_V1_VaultEntry {
        var entry = Gryonixnexusd_V1_VaultEntry()
        entry.id = id
        entry.host = host
        entry.title = title
        entry.website = website ?? ""
        entry.login = login
        entry.password = password
        entry.token = token
        entry.updatedAt = updatedAt.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        entry.updatedBy = updatedBy
        return entry
    }
}
