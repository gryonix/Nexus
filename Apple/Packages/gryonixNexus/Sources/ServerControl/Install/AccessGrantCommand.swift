import Foundation

public enum AccessGrantCommand {
    public static let marker = "GRYONIXNEXUS_GRANT_OK"

    public static func command(publicKey: String) -> String {
        let script = [
            "set -e",
            "k=\(ShellQuoting.singleQuoted(publicKey))",
            "u=${SUDO_USER:-$(id -un)}",
            "h=$(getent passwd \"$u\" | cut -d: -f6)",
            "[ -n \"$h\" ] || { echo \"no home directory for $u\" >&2; exit 1; }",
            "mkdir -p \"$h/.ssh\"",
            "chmod 700 \"$h/.ssh\"",
            "touch \"$h/.ssh/authorized_keys\"",
            "chmod 600 \"$h/.ssh/authorized_keys\"",
            "grep -qxF \"$k\" \"$h/.ssh/authorized_keys\" || printf \"%s\\n\" \"$k\" >> \"$h/.ssh/authorized_keys\"",
            "if [ \"$(id -u)\" = 0 ]; then chown -R \"$u:\" \"$h/.ssh\"; fi",
            "echo \"\(marker) $u\""
        ].joined(separator: "; ")
        return "sh -c \(ShellQuoting.singleQuoted(script))"
    }
}
