#if os(macOS)
import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MenuBarSettings: ObservableObject {
    static let shared = MenuBarSettings()

    private enum Keys {
        static let showsItem = "menuBar.shows"
        static let accessoryOnly = "menuBar.accessoryOnly"
    }

    @Published var showsItem: Bool {
        didSet {
            guard showsItem != oldValue else { return }
            let value = showsItem
            DispatchQueue.main.async { [weak self] in
                guard let self, self.showsItem == value else { return }
                self.defaults.set(value, forKey: Keys.showsItem)
                if !value { self.accessoryOnly = false }
                self.applyActivationPolicy()
            }
        }
    }

    @Published var accessoryOnly: Bool {
        didSet {
            guard accessoryOnly != oldValue else { return }
            let value = accessoryOnly
            DispatchQueue.main.async { [weak self] in
                guard let self, self.accessoryOnly == value else { return }
                self.defaults.set(value, forKey: Keys.accessoryOnly)
                self.applyActivationPolicy()
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsItem = defaults.object(forKey: Keys.showsItem) as? Bool ?? true
        accessoryOnly = defaults.bool(forKey: Keys.accessoryOnly)
    }

    /// Applies the Dock decision to the running app
    func applyActivationPolicy() {
        let wanted: NSApplication.ActivationPolicy = (showsItem && accessoryOnly)
            ? .accessory : .regular
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
#endif
