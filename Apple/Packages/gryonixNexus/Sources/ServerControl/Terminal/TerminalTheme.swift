import Foundation

/// A terminal colour scheme: 16 ANSI colours plus four more.
public struct TerminalTheme: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var background: String
    public var foreground: String
    public var cursor: String
    public var selection: String
    public var ansi: [String]

    public init(id: String, name: String, background: String, foreground: String,
                cursor: String, selection: String, ansi: [String]) {
        self.id = id
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
    }

    public var isValid: Bool {
        ansi.count == 16 && ([background, foreground, cursor, selection] + ansi)
            .allSatisfy { Self.rgb($0) != nil }
    }

    public var isDark: Bool {
        guard let (red, green, blue) = Self.rgb(background) else { return true }
        return 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue) < 128
    }

    public static func rgb(_ hex: String) -> (UInt8, UInt8, UInt8)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (UInt8(value >> 16 & 255), UInt8(value >> 8 & 255), UInt8(value & 255))
    }

    public static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
