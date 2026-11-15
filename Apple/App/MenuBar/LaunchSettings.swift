#if os(macOS)
import AppKit
import Foundation
import ServiceManagement
import SwiftUI

/// Login item, a quiet start, and the tunnel at launch
@MainActor
final class LaunchSettings: ObservableObject {
    static let shared = LaunchSettings()

    private enum Keys {
        static let startsInBackground = "launch.startsInBackground"
        static let connectsTunnel = "launch.connectsTunnel"
    }

    /// Registered with the system as a login item
    @Published private(set) var opensAtLogin = false
    /// Registered, but waiting for the user in System Settings
    @Published private(set) var needsApproval = false
    @Published private(set) var loginItemError: String?

    @Published var startsInBackground: Bool {
        didSet { defaults.set(startsInBackground, forKey: Keys.startsInBackground) }
    }

    @Published var connectsTunnel: Bool {
        didSet { defaults.set(connectsTunnel, forKey: Keys.connectsTunnel) }
    }

    private let defaults: UserDefaults

    /// Time for the engine to adopt a tunnel already running
    static let tunnelSettle = Duration.seconds(2)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        startsInBackground = defaults.bool(forKey: Keys.startsInBackground)
        connectsTunnel = defaults.bool(forKey: Keys.connectsTunnel)
        refreshLoginItem()
    }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }

    func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Runs once, when the app has finished launching
    func applyAtLaunch() {
        if startsInBackground {
            DockPresence.shared.holdFirstWindow()
        }
        if connectsTunnel {
            Task { await self.connectTunnel() }
        }
    }

    /// Brings up the chosen tunnel unless one already runs
    private func connectTunnel() async {
        let tunnel = TunnelController.shared
        try? await Task.sleep(for: Self.tunnelSettle)
        guard let selected = tunnel.selected, !tunnel.status.isActive, !tunnel.status.isBusy else { return }
        // Skips the lock sheet at launch
        guard LicenseStore.isUnlocked || DemoServer.isDemo(selected.serverID) else { return }
        await tunnel.connect()
    }
}

struct LaunchSettingsSection: View {
    @ObservedObject private var settings = LaunchSettings.shared
    @ObservedObject private var menuBar = MenuBarSettings.shared

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { settings.opensAtLogin },
                                 set: { settings.setOpensAtLogin($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at login")
                    Text("Starts gryonixNexus when you sign in to this Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if settings.needsApproval {
                Button("Allow in System Settings…") { settings.openLoginItemsSettings() }
                    .infoNote("Login items", "macOS asks you to allow the login item once, under General → Login Items.")
            }
            if let error = settings.loginItemError {
                Text(verbatim: error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Toggle(isOn: $settings.startsInBackground) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start in the background")
                    Text(menuBar.showsItem
                         ? "Opens no window at launch. The menu bar item and the tunnel stay ready."
                         : "Opens no window at launch. Click the Dock icon to open it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.connectsTunnel) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect the VPN at launch")
                    Text("Brings up the selected tunnel when the app starts, unless one already runs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Launch")
        }
        .onAppear { settings.refreshLoginItem() }
    }
}
#endif
