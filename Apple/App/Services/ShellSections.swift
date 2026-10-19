import Foundation
#if os(iOS)
import UIKit
#endif

/// The sections the shell actually shows, in the user's order
@MainActor
enum ShellSections {
    static func visible(order: [AppTab],
                        metricsRaw: String,
                        vpnRaw: String,
                        containersRaw: String,
                        terminalRaw: String) -> [AppTab] {
        let metrics = MetricsDisplaySettings.placement(from: metricsRaw)
        let vpn = VPNDisplaySettings.placement(from: vpnRaw)
        let containers = ContainersDisplaySettings.placement(from: containersRaw)
        let terminal = TerminalDisplaySettings.placement(from: terminalRaw)
        return order.filter { tab in
            switch tab {
            case .metrics: return metrics.showsDashboardTab
            case .vpn: return vpn.showsTab
            case .containers: return containers.showsTab
            case .terminal: return terminal.showsTab
            default: return true
            }
        }
    }
    static var barCapacity: Int {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? .max : 5
        #else
        .max
        #endif
    }

    /// The sections drawn as tabs, and the rest behind More
    static func onBar(_ visible: [AppTab]) -> [AppTab] {
        guard visible.count > barCapacity else { return visible }
        return Array(visible.prefix(barCapacity - 1))
    }

    static func behindMore(_ visible: [AppTab]) -> [AppTab] {
        guard visible.count > barCapacity else { return [] }
        return Array(visible.dropFirst(barCapacity - 1))
    }
}
