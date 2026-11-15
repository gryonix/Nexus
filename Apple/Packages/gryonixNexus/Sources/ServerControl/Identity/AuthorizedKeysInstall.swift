import Foundation

/// Adds a public key to a server user's authorized_keys
public enum AuthorizedKeysInstall {
    public static let added = "gryonix-key-added"
    public static let alreadyThere = "gryonix-key-present"

    /// Idempotent append, file mode 0600
    public static func command(publicKeyLine: String) -> String? {
        let parts = publicKeyLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[1].allSatisfy(isBase64) else { return nil }
        let line = ShellQuoting.singleQuoted(parts.joined(separator: " "))
        let blob = ShellQuoting.singleQuoted(String(parts[1]))
        let file = "\"$HOME/.ssh/authorized_keys\""
        return [
            "umask 077",
            "mkdir -p \"$HOME/.ssh\"",
            "chmod 700 \"$HOME/.ssh\"",
            "touch \(file)",
            "chmod 600 \(file)",
            "if grep -qF -- \(blob) \(file); then echo \(alreadyThere); else "
                + "{ [ -z \"$(tail -c1 \(file))\" ] || echo >> \(file); } "
                + "&& printf '%s\\n' \(line) >> \(file) && echo \(added); fi",
        ].joined(separator: " && ")
    }

    public enum Outcome: Equatable, Sendable {
        case added
        case alreadyThere
        case failed
    }

    public static func outcome(of result: ExecResult) -> Outcome {
        guard result.exitCode == 0 else { return .failed }
        if result.stdout.contains(added) { return .added }
        return result.stdout.contains(alreadyThere) ? .alreadyThere : .failed
    }

    private static func isBase64(_ char: Character) -> Bool {
        char.isASCII && (char.isLetter || char.isNumber || "+/=".contains(char))
    }
}
