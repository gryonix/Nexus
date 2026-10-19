import Foundation

public enum ShellQuoting {
    public static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The value itself when plain, quoted otherwise
    public static func argument(_ value: String) -> String {
        let plain = !value.isEmpty && value.unicodeScalars.allSatisfy {
            ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0))))
                || "_@%+=:,./-".unicodeScalars.contains($0)
        }
        return plain ? value : singleQuoted(value)
    }
}
