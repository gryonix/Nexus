import Foundation
import ServerControl
import SwiftUI

enum MetricsDisplaySettings {
    static let indicatorStyleKey = "metrics.indicatorStyle"
    static let historyInlineKey = "metrics.historyInline"
    static let historyAutoScaleKey = "metrics.historyAutoScale"
    /// Where metrics are reachable from — see `MetricsPlacement`
    static let placementKey = "metrics.placement"
    static let cardColumnsKey = "servers.cardColumns"

    static func indicatorStyle(from raw: String) -> MetricsIndicatorStyle {
        MetricsIndicatorStyle(rawValue: raw) ?? .bars
    }

    static func placement(from raw: String) -> MetricsPlacement {
        MetricsPlacement(rawValue: raw) ?? .both
    }

    static func cardColumns(from raw: String) -> ServerCardColumns {
        ServerCardColumns(rawValue: raw) ?? .one
    }
}

enum ServerCardColumns: String, CaseIterable, Identifiable {
    case one
    /// Two half-width cards per row
    case two

    var id: String { rawValue }

    var count: Int { self == .one ? 1 : 2 }

    /// The per-server size this setting stands for
    var cardSize: ServerCardSize { self == .one ? .wide : .compact }
}

enum MetricsPlacement: String, CaseIterable, Identifiable, SegmentPlacement {
    case dashboard
    /// Only inside a server, where it has always been
    case server
    /// Both — the default, and what shipped before this setting existed
    case both

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .dashboard: return "Metrics tab"
        case .server: return "Inside the server"
        case .both: return "Both"
        }
    }

    var showsDashboardTab: Bool { self != .server }
    var showsInsideServer: Bool { self != .dashboard }
}
