import Foundation

/// Shell single-quoting for values baked into generated setup scripts (e.g
enum ShellQuoting {
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
