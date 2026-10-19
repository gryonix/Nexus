import Foundation
import SwiftUI

/// UserDefaults keys for where VPN client management is reachable from
enum VPNDisplaySettings {
    /// See `VPNPlacement`
    static let placementKey = "vpn.placement"

    static func placement(from raw: String) -> VPNPlacement {
        VPNPlacement(rawValue: raw) ?? .both
    }
}

enum VPNPlacement: String, CaseIterable, Identifiable, SegmentPlacement {
    case tab
    /// Only inside a server, under its VPN service
    case server
    /// Both — the default
    case both

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .tab: return "VPN tab"
        case .server: return "Inside the server"
        case .both: return "Both"
        }
    }

    var showsTab: Bool { self != .server }
    var showsInsideServer: Bool { self != .tab }
}
