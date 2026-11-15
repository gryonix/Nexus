import Foundation

/// Removes the app SSH key from a forgotten server
public enum AppKeyRevocation {
    /// What else lets someone sign in to one machine
    public struct AccessCheck: Sendable, Hashable {
        /// Keys in the login user's authorized_keys other than the app's
        public let otherKeys: Int
        /// sshd's password login; nil when it could not be read
        public let passwordLogin: Bool?
        /// Whether the app's key is on the machine at all
        public let keyPresent: Bool

        public init(otherKeys: Int, passwordLogin: Bool?, keyPresent: Bool) {
            self.otherKeys = otherKeys
            self.passwordLogin = passwordLogin
            self.keyPresent = keyPresent
        }

        /// Removing the key would leave no known way in
        public var isLastWayIn: Bool {
            keyPresent && otherKeys == 0 && passwordLogin != true
        }
    }

    /// The base64 body of an OpenSSH public key line
    public static func keyBody(of publicKey: String) -> String? {
        let fields = publicKey.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2 else { return nil }
        let body = String(fields[1])
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard body.count >= 16, body.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return body
    }

    /// Counts the other ways in, without changing anything
    public static func checkScript(keyBody: String) -> String {
        """
        f="$HOME/.ssh/authorized_keys"
        present=no; others=0
        if [ -f "$f" ]; then
          grep -qF '\(keyBody)' "$f" && present=yes
          others=$(grep -v '^[[:space:]]*#' "$f" | grep -v '^[[:space:]]*$' | grep -cvF '\(keyBody)' || true)
        fi
        pw=$( (sudo -n sshd -T 2>/dev/null || sshd -T 2>/dev/null) | awk '$1=="passwordauthentication"{print $2; exit}')
        echo "present=$present"
        echo "others=${others:-0}"
        echo "password=${pw:-unknown}"
        """
    }

    /// Reads the check's answer; nil when it is not one
    public static func parse(_ output: String) -> AccessCheck? {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        guard let present = values["present"], let others = values["others"].flatMap({ Int($0) }) else {
            return nil
        }
        let password: Bool?
        switch values["password"] {
        case "yes": password = true
        case "no": password = false
        default: password = nil
        }
        return AccessCheck(otherKeys: others, passwordLogin: password, keyPresent: present == "yes")
    }

    /// Drops every line carrying the key, keeping the file's mode
    public static func removeScript(keyBody: String) -> String {
        """
        f="$HOME/.ssh/authorized_keys"
        [ -f "$f" ] || exit 0
        t=$(mktemp "$f.XXXXXX") || exit 1
        grep -vF '\(keyBody)' "$f" > "$t" || true
        chmod 600 "$t"
        mv "$t" "$f"
        ! grep -qF '\(keyBody)' "$f"
        """
    }

    /// Machines behind other machines come first
    public static func removalOrder(_ nodes: [DeploymentNode]) -> [DeploymentNode] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        func depth(_ node: DeploymentNode) -> Int {
            var hops = 0
            var next = node.routedThrough
            var seen: Set<UUID> = [node.id]
            while let id = next, let parent = byID[id], seen.insert(id).inserted {
                hops += 1
                next = parent.routedThrough
            }
            return hops
        }
        return nodes.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (depth(lhs.element), depth(rhs.element))
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
