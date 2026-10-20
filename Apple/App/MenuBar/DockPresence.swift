#if os(macOS)
import AppKit

/// No Dock icon while only the menu bar remains
@MainActor
final class DockPresence {
    static let shared = DockPresence()

    private var observers: [NSObjectProtocol] = []

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
    }

    private func windowClosed(_ closing: NSWindow?) {
        guard MenuBarSettings.shared.showsItem, NSApp.activationPolicy() == .regular else { return }
        let stillOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && Self.isAppWindow($0) }
        if !stillOpen { NSApp.setActivationPolicy(.accessory) }
    }

    private func windowOpened(_ window: NSWindow?) {
        guard let window, Self.isAppWindow(window), !MenuBarSettings.shared.accessoryOnly,
              NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A real window, not the menu bar's panel
    static func isAppWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain && !(window is NSPanel)
    }
}
#endif
