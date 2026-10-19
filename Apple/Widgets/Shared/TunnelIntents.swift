import AppIntents
import Foundation
import VPNTunnel

/// What an intent actually acts on
@MainActor
protocol TunnelIntentTarget: AnyObject {
    func intentConnect() async
    func intentDisconnect() async
    func intentIslandStop() async
    func intentOpenApp()
}

@MainActor
enum TunnelIntents {
    /// Set once, by the app, at launch
    static var target: (any TunnelIntentTarget)?
}

@available(iOS 17.0, macOS 14.0, *)
struct ConnectTunnelIntent: AppIntent {
    static var title: LocalizedStringResource = "Connect the VPN"
    static var description = IntentDescription("Brings up the selected tunnel on this device.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await TunnelIntents.target?.intentConnect()
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct DisconnectTunnelIntent: AppIntent {
    static var title: LocalizedStringResource = "Disconnect the VPN"
    static var description = IntentDescription("Takes down the tunnel running on this device.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await TunnelIntents.target?.intentDisconnect()
        return .result()
    }
}

/// The Control Center toggle's intent: one value, on or off
@available(iOS 18.0, macOS 26.0, *)
struct ToggleTunnelIntent: SetValueIntent {
    static var title: LocalizedStringResource = "VPN"
    static var description = IntentDescription("Turns this device's tunnel on or off.")
    static var openAppWhenRun = true

    @Parameter(title: "Connected")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        if value {
            await TunnelIntents.target?.intentConnect()
        } else {
            await TunnelIntents.target?.intentDisconnect()
        }
        return .result()
    }
}

/// The widget's "refresh" button
@available(iOS 17.0, macOS 14.0, *)
struct RefreshFleetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh devices"
    static var description = IntentDescription("Opens gryonixNexus and re-reads the devices on every server.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        TunnelIntents.target?.intentOpenApp()
        return .result()
    }
}

/// The phrases Siri and Shortcuts offer without anybody configuring anything
@available(iOS 17.0, macOS 14.0, *)
struct TunnelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectTunnelIntent(),
                    phrases: ["Connect \(.applicationName)",
                              "Turn on \(.applicationName)"],
                    shortTitle: "Connect",
                    systemImageName: "lock.shield.fill")
        AppShortcut(intent: DisconnectTunnelIntent(),
                    phrases: ["Disconnect \(.applicationName)",
                              "Turn off \(.applicationName)"],
                    shortTitle: "Disconnect",
                    systemImageName: "lock.open")
    }
}
