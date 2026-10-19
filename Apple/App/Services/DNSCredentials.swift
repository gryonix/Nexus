import Foundation

struct DNSCredential: Identifiable, Equatable {
    let id: String
    var name: String
    var kind: DNSProviderKind
}

@MainActor
final class DNSCredentials: ObservableObject {
    static let shared = DNSCredentials()

    nonisolated static let idsKey = "dns.credentials"
    nonisolated static let selectedKey = "dns.credentials.selected"
    nonisolated static let namePrefix = "dns.credential.name."
    nonisolated static let kindPrefix = "dns.credential.kind."

    nonisolated static let cloudflareFirstID = "default"
    nonisolated static func adoptedID(for kind: DNSProviderKind) -> String {
        "kind.\(kind.rawValue)"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var all: [DNSCredential] {
        (defaults.stringArray(forKey: Self.idsKey) ?? []).map(credential(_:))
    }

    /// The credential the app publishes with when nothing else says
    var selectedID: String? {
        get {
            let stored = defaults.string(forKey: Self.selectedKey)
            if let stored, all.contains(where: { $0.id == stored }) { return stored }
            return all.first?.id
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.selectedKey)
        }
    }

    var selected: DNSCredential? { all.first { $0.id == selectedID } }

    func credential(_ id: String) -> DNSCredential {
        DNSCredential(id: id, name: name(of: id), kind: kind(of: id))
    }

    func name(of id: String) -> String {
        storedName(of: id) ?? kind(of: id).displayName
    }

    func storedName(of id: String) -> String? {
        defaults.string(forKey: Self.namePrefix + id)
    }

    func kind(of id: String) -> DNSProviderKind {
        defaults.string(forKey: Self.kindPrefix + id)
            .flatMap(DNSProviderKind.init(rawValue:)) ?? .cloudflare
    }

    /// A new, empty credential
    @discardableResult
    func add(named name: String, kind: DNSProviderKind) -> DNSCredential {
        objectWillChange.send()
        let id = UUID().uuidString
        defaults.set(all.map(\.id) + [id], forKey: Self.idsKey)
        write(name: name, id: id, kind: kind)
        if defaults.string(forKey: Self.selectedKey) == nil {
            defaults.set(id, forKey: Self.selectedKey)
        }
        return credential(id)
    }

    func update(_ id: String, name: String, kind: DNSProviderKind) {
        objectWillChange.send()
        write(name: name, id: id, kind: kind)
    }

    /// Forget a credential and every token under it
    func remove(_ id: String) async {
        let credential = credential(id)
        await DNSCredentialTokenStore.clear(credential)
        await DNSCredentialTokenStore.clearTunnelToken(credential)
        objectWillChange.send()
        defaults.removeObject(forKey: Self.namePrefix + id)
        defaults.removeObject(forKey: Self.kindPrefix + id)
        let left = all.map(\.id).filter { $0 != id }
        defaults.set(left, forKey: Self.idsKey)
        if defaults.string(forKey: Self.selectedKey) == id {
            defaults.set(left.first, forKey: Self.selectedKey)
        }
    }

    private func write(name: String, id: String, kind: DNSProviderKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.namePrefix + id)
        } else {
            defaults.set(trimmed, forKey: Self.namePrefix + id)
        }
        defaults.set(kind.rawValue, forKey: Self.kindPrefix + id)
    }

    // MARK: - What the two old stores left behind

    func adoptStoredTokensIfNeeded() async {
        guard defaults.stringArray(forKey: Self.idsKey) == nil else { return }
        var adopted: [(id: String, name: String, kind: DNSProviderKind)] = []

        let storedAccounts = defaults.stringArray(forKey: Legacy.cloudflareIDsKey)
        for id in storedAccounts ?? [Self.cloudflareFirstID] {
            let credential = DNSCredential(id: id, name: "", kind: .cloudflare)
            let hasDNS = await DNSCredentialTokenStore.load(credential) != nil
            let hasTunnel = await DNSCredentialTokenStore.loadTunnelToken(credential) != nil
            guard storedAccounts != nil || hasDNS || hasTunnel else { continue }
            let name = defaults.string(forKey: Legacy.cloudflareNamePrefix + id)
                ?? DNSProviderKind.cloudflare.displayName
            adopted.append((id, name, .cloudflare))
        }

        for kind in DNSProviderKind.allCases where kind != .cloudflare {
            let id = Self.adoptedID(for: kind)
            let probe = DNSCredential(id: id, name: "", kind: kind)
            guard await DNSCredentialTokenStore.load(probe) != nil else { continue }
            adopted.append((id, kind.displayName, kind))
        }

        guard !adopted.isEmpty else { return }
        objectWillChange.send()
        for one in adopted { write(name: one.name, id: one.id, kind: one.kind) }
        defaults.set(adopted.map(\.id), forKey: Self.idsKey)
        let previousKind = defaults.string(forKey: Legacy.defaultKindKey)
            .flatMap(DNSProviderKind.init(rawValue:)) ?? .cloudflare
        let previous = previousKind == .cloudflare
            ? defaults.string(forKey: Legacy.cloudflareSelectedKey) ?? Self.cloudflareFirstID
            : Self.adoptedID(for: previousKind)
        defaults.set(adopted.contains { $0.id == previous } ? previous : adopted[0].id,
                     forKey: Self.selectedKey)
    }

    /// The keys the two old stores wrote
    enum Legacy {
        static let cloudflareIDsKey = "cloudflare.accounts"
        static let cloudflareSelectedKey = "cloudflare.selectedAccount"
        static let cloudflareNamePrefix = "cloudflare.name."
        static let defaultKindKey = "dns.defaultProviderKind"
    }

    // MARK: - Which Keychain item a credential's token lives in

    nonisolated static func tokenItem(id: String, kind: DNSProviderKind) -> String {
        if kind == .cloudflare {
            return id == cloudflareFirstID ? "cloudflare-api-token" : "cloudflare-api-token.\(id)"
        }
        if id == adoptedID(for: kind) { return "dns-provider-token.\(kind.rawValue)" }
        return "dns-credential-token.\(id)"
    }

    nonisolated static func tunnelItem(id: String) -> String {
        id == cloudflareFirstID ? "cloudflare-tunnel-api-token"
            : "cloudflare-tunnel-api-token.\(id)"
    }

    nonisolated static var currentCloudflareID: String {
        let defaults = UserDefaults.standard
        let ids = defaults.stringArray(forKey: idsKey) ?? []
        func isCloudflare(_ id: String) -> Bool {
            (defaults.string(forKey: kindPrefix + id)
                .flatMap(DNSProviderKind.init(rawValue:)) ?? .cloudflare) == .cloudflare
        }
        if let selected = defaults.string(forKey: selectedKey),
           ids.contains(selected), isCloudflare(selected) {
            return selected
        }
        return ids.first(where: isCloudflare) ?? cloudflareFirstID
    }
}

/// A credential's tokens, in the Keychain and nowhere else
enum DNSCredentialTokenStore {
    static func load(_ credential: DNSCredential) async -> String? {
        await read(DNSCredentials.tokenItem(id: credential.id, kind: credential.kind))
    }

    static func save(_ token: String, for credential: DNSCredential) async throws {
        try await write(token, DNSCredentials.tokenItem(id: credential.id, kind: credential.kind))
    }

    static func clear(_ credential: DNSCredential) async {
        await delete(DNSCredentials.tokenItem(id: credential.id, kind: credential.kind))
    }

    static func loadTunnelToken(_ credential: DNSCredential) async -> String? {
        guard credential.kind == .cloudflare else { return nil }
        return await read(DNSCredentials.tunnelItem(id: credential.id))
    }

    static func saveTunnelToken(_ token: String, for credential: DNSCredential) async throws {
        try await write(token, DNSCredentials.tunnelItem(id: credential.id))
    }

    static func clearTunnelToken(_ credential: DNSCredential) async {
        await delete(DNSCredentials.tunnelItem(id: credential.id))
    }

    static func currentCloudflareTunnelToken() async -> String? {
        await read(DNSCredentials.tunnelItem(id: DNSCredentials.currentCloudflareID))
    }

    static func currentCloudflareDNSToken() async -> String? {
        await read(DNSCredentials.tokenItem(id: DNSCredentials.currentCloudflareID, kind: .cloudflare))
    }

    static func move(_ credential: DNSCredential, to kind: DNSProviderKind) async {
        guard kind != credential.kind else { return }
        let token = await load(credential)
        let tunnel = await loadTunnelToken(credential)
        await clear(credential)
        await clearTunnelToken(credential)
        var moved = credential
        moved.kind = kind
        if let token { try? await save(token, for: moved) }
        if let tunnel, kind == .cloudflare { try? await saveTunnelToken(tunnel, for: moved) }
    }

    private static func read(_ item: String) async -> String? {
        await Task.detached {
            let stored = try? KeychainStore().string(for: item)
            return (stored?.isEmpty ?? true) ? nil : stored
        }.value
    }

    private static func write(_ token: String, _ item: String) async throws {
        try await Task.detached { try KeychainStore().set(token, for: item) }.value
    }

    private static func delete(_ item: String) async {
        await Task.detached { try? KeychainStore().delete(item) }.value
    }
}
