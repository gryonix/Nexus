import Foundation
import SwiftUI

/// What the VPN island shows and in which colour
struct VPNIslandStyle: Codable, Hashable, Sendable {
    enum Tint: String, Codable, CaseIterable, Sendable {
        case status, blue, green, teal, purple, pink, orange, white

        /// `nil` follows the tunnel's state colour
        var color: Color? {
            switch self {
            case .status: return nil
            case .blue: return .blue
            case .green: return .green
            case .teal: return .teal
            case .purple: return .purple
            case .pink: return .pink
            case .orange: return .orange
            case .white: return .white
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .status: return "By state"
            case .blue: return "Blue"
            case .green: return "Green"
            case .teal: return "Teal"
            case .purple: return "Purple"
            case .pink: return "Pink"
            case .orange: return "Orange"
            case .white: return "White"
            }
        }
    }

    /// The small island's right-hand side
    enum CompactDetail: String, Codable, CaseIterable, Sendable {
        case timer, protocolName, traffic, nothing

        var title: LocalizedStringKey {
            switch self {
            case .timer: return "Connection time"
            case .protocolName: return "Protocol"
            case .traffic: return "Traffic"
            case .nothing: return "Nothing"
            }
        }
    }

    var tint: Tint = .blue
    var compactDetail: CompactDetail = .timer
    var showsTimer = true
    var showsProtocol = true
    var showsServer = true
    var showsTraffic = false
    /// The Lock Screen card's lines; nil means the defaults
    var lockScreen: VPNLockScreenStyle?
    /// The user's own protocol names, by their short name
    var protocolLabels: [String: String]?

    /// Characters the small island has room for
    static let labelLength = 8

    /// The user's name for a protocol, if any
    func ownLabel(for protocolName: String) -> String? {
        let own = protocolLabels?[VPNProtocolShortName.of(protocolName)]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return own.isEmpty ? nil : String(own.prefix(Self.labelLength))
    }

    /// What the small island calls a protocol
    func shortLabel(for protocolName: String) -> String {
        ownLabel(for: protocolName) ?? VPNProtocolShortName.of(protocolName)
    }

    /// What the expanded island and the card call it
    func fullLabel(for protocolName: String) -> String {
        ownLabel(for: protocolName) ?? protocolName
    }

    var lockScreenStyle: VPNLockScreenStyle {
        get { lockScreen ?? .standard }
        set { lockScreen = newValue }
    }

    /// Island defaults; the Lock Screen card keeps its settings
    var islandReset: VPNIslandStyle {
        var reset = VPNIslandStyle.standard
        reset.lockScreen = lockScreen
        return reset
    }

    static let standard = VPNIslandStyle()
    static let defaultsKey = "vpn.island.style"

    static func current(_ defaults: UserDefaults = .standard) -> VPNIslandStyle {
        guard let data = defaults.data(forKey: defaultsKey),
              let style = try? JSONDecoder().decode(VPNIslandStyle.self, from: data) else { return .standard }
        return style
    }

    func save(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func color(stateColor: Color) -> Color {
        tint.color ?? stateColor
    }
}

/// What the Lock Screen card shows
struct VPNLockScreenStyle: Codable, Hashable, Sendable {
    var showsTimer = true
    var showsServer = true
    var showsProtocol = true
    var showsTraffic = true
    var showsStopButton = true

    static let standard = VPNLockScreenStyle()
}

/// "1.4G": bytes in the few characters the small island allows
enum CompactBytes {
    static func of(_ value: Int64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var amount = Double(max(value, 0))
        var unit = 0
        while amount >= 1000, unit < units.count - 1 {
            amount /= 1024
            unit += 1
        }
        let digits = amount < 10 && unit > 0 ? 1 : 0
        return String(format: "%.\(digits)f", amount) + units[unit]
    }
}

/// Short protocol names for the small island
enum VPNProtocolShortName {
    /// Every protocol a user can rename, by its short name
    static let renamable: [(short: String, name: String)] = [
        ("WG", "WireGuard"), ("AWG", "AmneziaWG"), ("SS", "Shadowsocks"),
        ("VLESS", "VLESS / Reality"), ("OVPN", "OpenVPN"),
    ]

    static func of(_ name: String) -> String {
        switch name.lowercased() {
        case let text where text.contains("amnezia"): return "AWG"
        case let text where text.contains("wireguard"): return "WG"
        case let text where text.contains("shadowsocks"): return "SS"
        case let text where text.contains("vless") || text.contains("reality") || text.contains("xray"): return "VLESS"
        case let text where text.contains("openvpn"): return "OVPN"
        default: return String(name.prefix(5))
        }
    }
}
