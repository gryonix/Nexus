public struct PrivilegedCommand: Sendable, Hashable {
    /// Absolute binary path as it appears in sudoers, e.g
    public let binaryPath: String
    /// Verbatim argument string, e.g
    public let arguments: String

    public init(binaryPath: String, arguments: String) {
        self.binaryPath = binaryPath
        self.arguments = arguments
    }

    /// The command the app sends over SSH
    public var command: String {
        let directory = binaryPath.split(separator: "/").dropLast().joined(separator: "/")
        let securePath = ["usr/local/sbin", "usr/local/bin", "usr/sbin", "usr/bin", "sbin", "bin"]
        let name = securePath.contains(directory)
            ? binaryPath.split(separator: "/").last.map(String.init) ?? binaryPath
            : binaryPath
        return arguments.isEmpty ? "sudo \(name)" : "sudo \(name) \(arguments)"
    }

    public func sudoersLine(user: String) -> String {
        let target = arguments.isEmpty ? binaryPath : "\(binaryPath) \(arguments)"
        return "\(user) ALL=(ALL) NOPASSWD: \(target)"
    }
}
