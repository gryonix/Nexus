import Foundation
import ServerControl

enum ProxyStore {
    private static let key = "proxies.list"

    static func all(defaults: UserDefaults = .standard) -> [ProxyProfile] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([ProxyProfile].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ list: [ProxyProfile], defaults: UserDefaults = .standard) {
        guard !list.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }

    static func profile(_ id: UUID?, defaults: UserDefaults = .standard) -> ProxyProfile? {
        guard let id else { return nil }
        return all(defaults: defaults).first { $0.id == id }
    }

    static func remove(_ id: UUID, defaults: UserDefaults = .standard) {
        save(all(defaults: defaults).filter { $0.id != id }, defaults: defaults)
        ProxyPasswordStore.delete(id)
    }
}

enum ProxyPasswordStore {
    private static func account(_ id: UUID) -> String {
        "gryonixnexus.proxy.\(id.uuidString)"
    }

    static func password(_ id: UUID, keychain: KeychainStore = KeychainStore()) -> String? {
        try? keychain.string(for: account(id))
    }

    static func save(_ password: String, for id: UUID, keychain: KeychainStore = KeychainStore()) {
        if password.isEmpty {
            try? keychain.delete(account(id))
        } else {
            try? keychain.set(password, for: account(id))
        }
    }

    static func delete(_ id: UUID, keychain: KeychainStore = KeychainStore()) {
        try? keychain.delete(account(id))
    }
}
