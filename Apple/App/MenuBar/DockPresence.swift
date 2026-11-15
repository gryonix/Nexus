#if os(macOS)
import AppKit
import OSLog

/// No Dock icon while only the menu bar remains
@MainActor
final class DockPresence {
    static let shared = DockPresence()

    /// Holds the first window of this launch closed
    private(set) var holdsFirstWindow = false
    private weak var heldWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private static let log = Logger(subsystem: "com.skaymer.gryonixnexus", category: "dock")

    /// Logs the Dock policy and the toggles behind it
    static func note(_ moment: String) {
        let policy = NSApp.activationPolicy() == .regular ? "regular" : "accessory"
        let menuBar = MenuBarSettings.shared
        let windows = NSApp.windows.filter { $0.isVisible && isAppWindow($0) }.count
        let text = "\(moment): policy \(policy) menuBar \(menuBar.showsItem) menuBarOnly \(menuBar.accessoryOnly) "
            + "background \(LaunchSettings.shared.startsInBackground) windows \(windows)"
        log.notice("\(text, privacy: .public)")
    }

    /// Adds the Dock icon unless menu bar only
    func showForWindow() {
        guard !MenuBarSettings.shared.accessoryOnly, NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        Self.note("window asked for the Dock icon")
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                            queue: .main) { note in
            let closing = note.object as? NSWindow
            DispatchQueue.main.async { DockPresence.shared.windowClosed(closing) }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                            queue: .main) { note in
            let window = note.object as? NSWindow
            DispatchQueue.main.async { DockPresence.shared.windowOpened(window) }
        })
        // Also catches windows that never become key
        observers.append(center.addObserver(forName: NSWindow.didUpdateNotification, object: nil,
                                            queue: .main) { note in
            let window = note.object as? NSWindow
            DispatchQueue.main.async { DockPresence.shared.windowUpdated(window) }
        })
    }

    /// Closes the first app window that appears
    func holdFirstWindow() {
        holdsFirstWindow = true
        if let window = NSApp.windows.first(where: { $0.isVisible && Self.isAppWindow($0) }) {
            _ = hold(window)
        }
    }

    /// Closes a held window; true when closed
    private func hold(_ window: NSWindow) -> Bool {
        guard holdsFirstWindow, window.isVisible, Self.isAppWindow(window) else { return false }
        holdsFirstWindow = false
        heldWindow = window
        window.close()
        if !MenuBarSettings.shared.showsItem { NSApp.hide(nil) }
        Self.note("first window held closed")
        return true
    }

    private func windowClosed(_ closing: NSWindow?) {
        // A background launch keeps the Dock icon it chose
        if let closing, closing === heldWindow { return }
        guard MenuBarSettings.shared.showsItem, NSApp.activationPolicy() == .regular else { return }
        let stillOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && Self.isAppWindow($0) }
        guard !stillOpen else { return }
        NSApp.setActivationPolicy(.accessory)
        Self.note("last window closed")
    }

    private func windowUpdated(_ window: NSWindow?) {
        guard holdsFirstWindow, let window else { return }
        _ = hold(window)
    }

    private func windowOpened(_ window: NSWindow?) {
        guard let window else { return }
        if hold(window) { return }
        guard Self.isAppWindow(window), !MenuBarSettings.shared.accessoryOnly,
              NSApp.activationPolicy() != .regular else { return }
        showForWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A real window, not the menu bar's panel
    static func isAppWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain && !(window is NSPanel)
    }
}
#endif
