import ServerControl
import SwiftUI

enum ServerTint: String, CaseIterable, Identifiable {
    case blue, teal, green, orange, pink, purple, red, gray

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .blue: return "Blue"
        case .teal: return "Teal"
        case .green: return "Green"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .red: return "Red"
        case .gray: return "Gray"
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .red: return .red
        case .gray: return .gray
        }
    }
}

/// Display names for the per-server card size
extension ServerCardSize {
    var localizedName: LocalizedStringKey {
        switch self {
        case .wide: return "Wide card"
        case .compact: return "Half-width card"
        }
    }
}

/// The SF Symbols offered as a server icon
enum ServerIcon {
    static let defaultSymbol = "server.rack"

    static let choices: [String] = [
        "server.rack", "house.fill", "externaldrive.fill", "internaldrive.fill",
        "network", "lock.shield.fill", "envelope.fill", "cloud.fill",
        "bolt.horizontal.fill", "globe", "cpu.fill", "tray.full.fill",
    ]
}

extension Deployment {
    /// The card icon: the user's choice, else the default
    var displaySymbol: String { iconSymbol ?? ServerIcon.defaultSymbol }

    var displayTint: Color? {
        tintName.flatMap { ServerTint(rawValue: $0)?.color }
    }
}
