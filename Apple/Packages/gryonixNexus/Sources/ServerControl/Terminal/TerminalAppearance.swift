import Foundation

public enum TerminalCursorShape: String, Codable, CaseIterable, Sendable {
    case block, bar, underline
}

/// How terminals look: themes, font, cursor and backdrop.
public struct TerminalAppearance: Codable, Equatable, Sendable {
    public static let fontSizeRange: ClosedRange<Double> = 8...32
    public static let opacityRange: ClosedRange<Double> = 0.3...1

    public var followSystem = true
    public var darkThemeID = TerminalThemes.defaultDarkID
    public var lightThemeID = TerminalThemes.defaultLightID
    public var fixedThemeID = TerminalThemes.defaultDarkID
    public var fontName: String?
    public var fontSize = 13.0
    public var cursorShape = TerminalCursorShape.block
    public var cursorBlink = true
    public var opacity = 1.0
    public var blur = false
    public var customThemes: [TerminalTheme] = []
    public var serverThemes: [String: String] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case followSystem, darkThemeID, lightThemeID, fixedThemeID, fontName, fontSize
        case cursorShape, cursorBlink, opacity, blur, customThemes, serverThemes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        followSystem = read(.followSystem, true)
        darkThemeID = read(.darkThemeID, TerminalThemes.defaultDarkID)
        lightThemeID = read(.lightThemeID, TerminalThemes.defaultLightID)
        fixedThemeID = read(.fixedThemeID, TerminalThemes.defaultDarkID)
        fontName = try? values.decodeIfPresent(String.self, forKey: .fontName)
        fontSize = read(.fontSize, 13.0)
        cursorShape = read(.cursorShape, .block)
        cursorBlink = read(.cursorBlink, true)
        opacity = read(.opacity, 1.0)
        blur = read(.blur, false)
        customThemes = read(.customThemes, [])
        serverThemes = read(.serverThemes, [:])
    }

    public var allThemes: [TerminalTheme] { TerminalThemes.builtIn + customThemes }

    /// The theme for a server, or the system mode.
    public func theme(isDark: Bool, server: String?) -> TerminalTheme {
        let id = server.flatMap { serverThemes[$0] }
            ?? (followSystem ? (isDark ? darkThemeID : lightThemeID) : fixedThemeID)
        return TerminalThemes.find(id, custom: customThemes)
            ?? TerminalThemes.find(isDark ? TerminalThemes.defaultDarkID : TerminalThemes.defaultLightID)!
    }

    public mutating func save(_ theme: TerminalTheme) {
        if let index = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[index] = theme
        } else {
            customThemes.append(theme)
        }
    }

    public mutating func removeCustom(_ id: String) {
        customThemes.removeAll { $0.id == id }
        serverThemes = serverThemes.filter { $0.value != id }
        if darkThemeID == id { darkThemeID = TerminalThemes.defaultDarkID }
        if lightThemeID == id { lightThemeID = TerminalThemes.defaultLightID }
        if fixedThemeID == id { fixedThemeID = TerminalThemes.defaultDarkID }
    }

    public mutating func zoom(by factor: Double) {
        fontSize = min(max((fontSize * factor).rounded(), Self.fontSizeRange.lowerBound),
                       Self.fontSizeRange.upperBound)
    }
}
