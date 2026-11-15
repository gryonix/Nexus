import AppIntents

struct GryonixShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectTunnelIntent(),
                    phrases: ["Connect \(.applicationName)"],
                    shortTitle: "Connect", systemImageName: "lock.shield.fill")
        AppShortcut(intent: DisconnectTunnelIntent(),
                    phrases: ["Disconnect \(.applicationName)"],
                    shortTitle: "Disconnect", systemImageName: "lock.open")
        AppShortcut(intent: ToggleVPNIntent(),
                    phrases: ["Toggle VPN in \(.applicationName)"],
                    shortTitle: "Toggle VPN", systemImageName: "arrow.left.arrow.right")
        AppShortcut(intent: ServerStatusIntent(),
                    phrases: ["Status of \(\.$server) in \(.applicationName)"],
                    shortTitle: "Server status", systemImageName: "server.rack")
        AppShortcut(intent: RestartServiceIntent(),
                    phrases: ["Restart \(\.$service) in \(.applicationName)"],
                    shortTitle: "Restart service", systemImageName: "arrow.clockwise")
        AppShortcut(intent: OpenServerIntent(),
                    phrases: ["Open \(\.$server) in \(.applicationName)"],
                    shortTitle: "Open server", systemImageName: "arrow.up.forward.app")
        AppShortcut(intent: AudioHubPlayPauseIntent(),
                    phrases: ["Play or pause music on \(\.$server) in \(.applicationName)"],
                    shortTitle: "Play or pause", systemImageName: "playpause.fill")
        AppShortcut(intent: SetAudioHubVolumeIntent(),
                    phrases: ["Set the volume on \(\.$server) in \(.applicationName)"],
                    shortTitle: "Audio hub volume", systemImageName: "speaker.wave.2.fill")
    }
}
