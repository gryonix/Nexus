import Foundation

@MainActor
enum ShellSectionVisibility {
    static func isOnBar(_ tab: AppTab,
                        tabs: TabBarSettings,
                        defaults: UserDefaults = .standard) -> Bool {
        guard tabs.isVisible(tab) else { return false }
        return placementShowsTab(tab, defaults: defaults)
    }

    /// Put the section on the bar, or take it off
    static func setOnBar(_ on: Bool, for tab: AppTab,
                         tabs: TabBarSettings,
                         defaults: UserDefaults = .standard) {
        guard tab.canBeHidden || on else { return }
        if on {
            tabs.setVisible(true, for: tab)
            if let key = placementKey(for: tab) {
                defaults.set(bothValue(for: tab), forKey: key)
            }
        } else if let key = placementKey(for: tab) {
            defaults.set(serverValue(for: tab), forKey: key)
        } else {
            tabs.setVisible(false, for: tab)
        }
    }

    private static func placementShowsTab(_ tab: AppTab, defaults: UserDefaults) -> Bool {
        switch tab {
        case .metrics:
            return MetricsDisplaySettings
                .placement(from: raw(MetricsDisplaySettings.placementKey, defaults,
                                     MetricsPlacement.both.rawValue)).showsDashboardTab
        case .vpn:
            return VPNDisplaySettings
                .placement(from: raw(VPNDisplaySettings.placementKey, defaults,
                                     VPNPlacement.both.rawValue)).showsTab
        case .containers:
            return ContainersDisplaySettings
                .placement(from: raw(ContainersDisplaySettings.placementKey, defaults,
                                     ContainersPlacement.server.rawValue)).showsTab
        case .terminal:
            return TerminalDisplaySettings
                .placement(from: raw(TerminalDisplaySettings.placementKey, defaults,
                                     TerminalPlacement.server.rawValue)).showsTab
        default:
            return true
        }
    }

    private static func raw(_ key: String, _ defaults: UserDefaults, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    private static func placementKey(for tab: AppTab) -> String? {
        switch tab {
        case .metrics: return MetricsDisplaySettings.placementKey
        case .vpn: return VPNDisplaySettings.placementKey
        case .containers: return ContainersDisplaySettings.placementKey
        case .terminal: return TerminalDisplaySettings.placementKey
        default: return nil
        }
    }

    private static func bothValue(for tab: AppTab) -> String {
        switch tab {
        case .metrics: return MetricsPlacement.both.rawValue
        case .vpn: return VPNPlacement.both.rawValue
        case .containers: return ContainersPlacement.both.rawValue
        case .terminal: return TerminalPlacement.both.rawValue
        default: return ""
        }
    }

    private static func serverValue(for tab: AppTab) -> String {
        switch tab {
        case .metrics: return MetricsPlacement.server.rawValue
        case .vpn: return VPNPlacement.server.rawValue
        case .containers: return ContainersPlacement.server.rawValue
        case .terminal: return TerminalPlacement.server.rawValue
        default: return ""
        }
    }
}
