import Foundation

public enum ShellUserCommand {
    /// Printed on success with the account that now exists
    public static let marker = "GRYONIXNEXUS_USER_OK"

    /// Names this refuses, and the refusal is the point
    public static let reservedNames: Set<String> = [
        "root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail",
        "news", "uucp", "proxy", "backup", "list", "irc", "nobody", "systemd",
        "sshd", "docker", "caddy"
    ]

    public static func isValidName(_ name: String) -> Bool {
        guard (1...32).contains(name.count) else { return false }
        guard !reservedNames.contains(name.lowercased()) else { return false }
        guard let first = name.first, first.isLowercase, first.isLetter else { return false }
        return name.allSatisfy { character in
            character.isLowercase && character.isLetter
                || character.isNumber
                || character == "_" || character == "-"
        }
    }

    /// - Parameters: - name: the account
    public static func command(name: String, publicKey: String, sudo: Bool) -> String? {
        guard isValidName(name) else { return nil }
        var script = [
            "set -e",
            "u=\(name)",
            "k=\(ShellQuoting.singleQuoted(publicKey))",
            "id \"$u\" >/dev/null 2>&1 || useradd -m -s /bin/bash \"$u\"",
            "h=$(getent passwd \"$u\" | cut -d: -f6)",
            "[ -n \"$h\" ] || { echo \"no home directory for $u\" >&2; exit 1; }",
            "mkdir -p \"$h/.ssh\"",
            "chmod 700 \"$h/.ssh\"",
            "touch \"$h/.ssh/authorized_keys\"",
            "chmod 600 \"$h/.ssh/authorized_keys\"",
            "grep -qxF \"$k\" \"$h/.ssh/authorized_keys\" || printf \"%s\\n\" \"$k\" >> \"$h/.ssh/authorized_keys\"",
            "chown -R \"$u:\" \"$h/.ssh\""
        ]
        if sudo {
            script += [
                "t=/etc/sudoers.d/.gryonixnexus-$u.tmp",
                "printf \"%s\\n\" \"$u ALL=(ALL) NOPASSWD:ALL\" > \"$t\"",
                "chmod 440 \"$t\"",
                "visudo -cf \"$t\" >/dev/null",
                "mv \"$t\" /etc/sudoers.d/gryonixnexus-$u"
            ]
        }
        script.append("echo \"\(marker) $u\"")
        return "sh -c \(ShellQuoting.singleQuoted(script.joined(separator: "; ")))"
    }
}
