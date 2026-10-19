import Foundation
import SwiftUI

/// Where the containers section is reachable from
enum ContainersDisplaySettings {
    static let placementKey = "containers.placement"

    static func placement(from raw: String) -> ContainersPlacement {
        ContainersPlacement(rawValue: raw) ?? .server
    }
}

enum ContainersPlacement: String, CaseIterable, Identifiable, SegmentPlacement {
    case section
    /// Only inside a server, alongside its metrics — the default
    case server
    case both

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .section: return "Containers tab"
        case .server: return "Inside the server"
        case .both: return "Both"
        }
    }

    var showsTab: Bool { self != .server }
    var showsInsideServer: Bool { self != .section }
}
