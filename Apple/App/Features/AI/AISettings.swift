import AIAssistant
import Foundation
import ServerControl

/// Provider choice, limits and notices; kept on this device only.
@MainActor
final class AISettings: ObservableObject {
    static let shared = AISettings()

    private enum Keys {
        static let provider = "ai.provider"
        static let model = "ai.model"
        static let server = "ai.ollamaServer"
        static let url = "ai.ollamaURL"
        static let limit = "ai.monthlyLimit"
        static let agreed = "ai.agreed"
        static let cloudSeen = "ai.cloudSeen"
        static let localSeen = "ai.localSeen"
        static let ledger = "ai.ledger"
    }

    private let defaults: UserDefaults
    private let keychain = KeychainStore()

    @Published var providerID: String { didSet { defaults.set(providerID, forKey: Keys.provider) } }
    @Published var model: String { didSet { defaults.set(model, forKey: Keys.model) } }
    @Published var ollamaServerID: String { didSet { defaults.set(ollamaServerID, forKey: Keys.server) } }
    @Published var ollamaURL: String { didSet { defaults.set(ollamaURL, forKey: Keys.url) } }
    @Published var monthlyLimit: Int { didSet { defaults.set(monthlyLimit, forKey: Keys.limit) } }
    @Published var agreed: Bool { didSet { defaults.set(agreed, forKey: Keys.agreed) } }
    @Published private(set) var ledger: AITokenLedger

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        providerID = defaults.string(forKey: Keys.provider) ?? ""
        model = defaults.string(forKey: Keys.model) ?? ""
        ollamaServerID = defaults.string(forKey: Keys.server) ?? ""
        ollamaURL = defaults.string(forKey: Keys.url) ?? ""
        monthlyLimit = defaults.integer(forKey: Keys.limit)
        agreed = defaults.bool(forKey: Keys.agreed)
        ledger = defaults.data(forKey: Keys.ledger)
            .flatMap { try? JSONDecoder().decode(AITokenLedger.self, from: $0) } ?? AITokenLedger()
    }

    var isConfigured: Bool { !providerID.isEmpty && !model.isEmpty }
    var isOllama: Bool { providerID == AIProviderConfig.ollamaID }
    var isOnDevice: Bool { providerID == AIProviderConfig.onDeviceID }
    var isLocal: Bool { isOllama || isOnDevice }

    func apiKey(for provider: String) -> String {
        (try? keychain.string(for: "ai.key.\(provider)")) ?? ""
    }

    func setAPIKey(_ key: String, for provider: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { try? keychain.delete("ai.key.\(provider)") } else {
            try? keychain.set(trimmed, for: "ai.key.\(provider)")
        }
        objectWillChange.send()
    }

    func hasSeenCloudNotice(_ provider: String) -> Bool { seen(Keys.cloudSeen).contains(provider) }
    var hasSeenLocalNotice: Bool { defaults.bool(forKey: Keys.localSeen) }

    func markCloudNoticeSeen(_ provider: String) {
        defaults.set(Array(seen(Keys.cloudSeen) + [provider]), forKey: Keys.cloudSeen)
    }

    func markLocalNoticeSeen() { defaults.set(true, forKey: Keys.localSeen) }

    private func seen(_ key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    var usedThisMonth: Int { ledger.used(at: Date()) }

    var budget: AIBudgetState {
        isLocal ? .unlimited : AITokenLedger.state(used: usedThisMonth, limit: monthlyLimit)
    }

    func record(input: Int, output: Int) {
        guard !isLocal else { return }
        ledger.add(tokens: input + output, at: Date())
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: Keys.ledger) }
    }

    func resolvedConfig(baseURL: String? = nil) -> AIProviderConfig {
        AIProviderConfig(providerID: providerID, model: model, baseURL: baseURL)
    }
}
