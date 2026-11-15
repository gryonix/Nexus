import Foundation

/// Reads an iTerm2 `.itermcolors` plist into a theme.
public enum ITermColorsImport {
    public enum Failure: Error { case notAColorFile, missingColour(String) }

    public static func theme(from data: Data, name: String) throws -> TerminalTheme {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = root as? [String: Any] else { throw Failure.notAColorFile }
        let ansi = try (0..<16).map { try colour("Ansi \($0) Color", in: dictionary) }
        let background = try colour("Background Color", in: dictionary)
        let foreground = try colour("Foreground Color", in: dictionary)
        return TerminalTheme(
            id: "custom-" + UUID().uuidString.lowercased(), name: name,
            background: background, foreground: foreground,
            cursor: (try? colour("Cursor Color", in: dictionary)) ?? foreground,
            selection: (try? colour("Selection Color", in: dictionary)) ?? ansi[8],
            ansi: ansi)
    }

    private static func colour(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let entry = dictionary[key] as? [String: Any],
              let red = number(entry["Red Component"]),
              let green = number(entry["Green Component"]),
              let blue = number(entry["Blue Component"]) else { throw Failure.missingColour(key) }
        return TerminalTheme.hex(red: red, green: green, blue: blue)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
