import Foundation
import ServerControl

/// The terminal look, saved here and in iCloud.
@MainActor
final class TerminalAppearanceStore: ObservableObject {
    static let shared = TerminalAppearanceStore()

    static let key = "terminal.appearance"

    @Published private(set) var appearance: TerminalAppearance

    private let local: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var observer: NSObjectProtocol?

    init(local: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore? = .default) {
        self.local = local
        self.cloud = cloud
        appearance = Self.decode(local.data(forKey: Self.key))
        guard let cloud else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.adoptCloud() }
        }
        cloud.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func update(_ change: (inout TerminalAppearance) -> Void) {
        var next = appearance
        change(&next)
        guard next != appearance else { return }
        appearance = next
        let data = try? JSONEncoder().encode(next)
        local.set(data, forKey: Self.key)
        cloud?.set(data, forKey: Self.key)
    }

    private func adoptCloud() {
        guard let data = cloud?.data(forKey: Self.key) else { return }
        local.set(data, forKey: Self.key)
        appearance = Self.decode(data)
    }

    private static func decode(_ data: Data?) -> TerminalAppearance {
        data.flatMap { try? JSONDecoder().decode(TerminalAppearance.self, from: $0) } ?? TerminalAppearance()
    }
}
