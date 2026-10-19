#if os(macOS)
import SwiftUI

@MainActor
struct AppCommands: Commands {
    @ObservedObject private var tabs = TabBarSettings.shared
    @AppStorage(MetricsDisplaySettings.placementKey)
    private var placementRaw = MetricsPlacement.both.rawValue
    @AppStorage(VPNDisplaySettings.placementKey)
    private var vpnPlacementRaw = VPNPlacement.both.rawValue
    @AppStorage(ContainersDisplaySettings.placementKey)
    private var containersPlacementRaw = ContainersPlacement.server.rawValue
    @AppStorage(TerminalDisplaySettings.placementKey)
    private var terminalPlacementRaw = TerminalPlacement.server.rawValue
    @FocusedValue(\.refreshAction) private var refreshAction

    /// Nine, because there are nine number keys
    private var numberedSections: [AppTab] {
        Array(ShellSections.visible(order: tabs.visibleTabs,
                                    metricsRaw: placementRaw,
                                    vpnRaw: vpnPlacementRaw,
                                    containersRaw: containersPlacementRaw,
                                    terminalRaw: terminalPlacementRaw).prefix(9))
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppNavigator.shared.show(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("Refresh") {
                guard let refreshAction else { return }
                Task { await refreshAction.run() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshAction == nil)
            Divider()
            ForEach(Array(numberedSections.enumerated()), id: \.element) { index, tab in
                Button {
                    AppNavigator.shared.show(tab)
                } label: {
                    Label { Text(tab.title) } icon: { tab.icon }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                  modifiers: .command)
            }
        }
    }
}
#endif
