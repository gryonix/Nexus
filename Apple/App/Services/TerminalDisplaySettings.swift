import Foundation
import SwiftUI

/// UserDefaults keys for where the terminal is reachable from
enum TerminalDisplaySettings {
    /// See `TerminalPlacement`
    static let placementKey = "terminal.placement"

    static func placement(from raw: String) -> TerminalPlacement {
        TerminalPlacement(rawValue: raw) ?? .server
    }
}

enum TerminalPlacement: String, CaseIterable, Identifiable, SegmentPlacement {
    case tab
    /// Only inside a server — the default
    case server
    case both

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .tab: return "Terminal tab"
        case .server: return "Inside the server"
        case .both: return "Both"
        }
    }

    var showsTab: Bool { self != .server }
    var showsInsideServer: Bool { self != .tab }
}
