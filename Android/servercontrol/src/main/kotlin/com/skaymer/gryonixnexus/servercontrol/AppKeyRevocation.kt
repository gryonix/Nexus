package com.skaymer.gryonixnexus.servercontrol

/** Removes the app SSH key from a forgotten server */
object AppKeyRevocation {
    /** What else lets someone sign in to one machine */
    data class AccessCheck(
        /** Keys in the login user's authorized_keys other than the app's */
        val otherKeys: Int,
        /** sshd's password login; null when it could not be read */
        val passwordLogin: Boolean?,
        /** Whether the app's key is on the machine at all */
        val keyPresent: Boolean,
    ) {
        /** Removing the key would leave no known way in */
        val isLastWayIn: Boolean get() = keyPresent && otherKeys == 0 && passwordLogin != true
    }

    private val BODY = Regex("^[A-Za-z0-9+/=]{16,}$")

    /** The base64 body of an OpenSSH public key line */
    fun keyBody(publicKey: String): String? {
        val fields = publicKey.trim().split(Regex("\\s+"))
        if (fields.size < 2) return null
        return fields[1].takeIf { BODY.matches(it) }
    }

    /** Counts the other ways in, without changing anything */
    fun checkScript(keyBody: String): String = """
        f="${'$'}HOME/.ssh/authorized_keys"
        present=no; others=0
        if [ -f "${'$'}f" ]; then
          grep -qF '$keyBody' "${'$'}f" && present=yes
          others=${'$'}(grep -v '^[[:space:]]*#' "${'$'}f" | grep -v '^[[:space:]]*${'$'}' | grep -cvF '$keyBody' || true)
        fi
        pw=${'$'}( (sudo -n sshd -T 2>/dev/null || sshd -T 2>/dev/null) | awk '${'$'}1=="passwordauthentication"{print ${'$'}2; exit}')
        echo "present=${'$'}present"
        echo "others=${'$'}{others:-0}"
        echo "password=${'$'}{pw:-unknown}"
    """.trimIndent()

    /** Reads the check's answer; null when it is not one */
    fun parse(output: String): AccessCheck? {
        val values = output.lines().mapNotNull { line ->
            val parts = line.split("=", limit = 2)
            if (parts.size == 2) parts[0].trim() to parts[1].trim() else null
        }.toMap()
        val present = values["present"] ?: return null
        val others = values["others"]?.toIntOrNull() ?: return null
        val password = when (values["password"]) {
            "yes" -> true
            "no" -> false
            else -> null
        }
        return AccessCheck(otherKeys = others, passwordLogin = password, keyPresent = present == "yes")
    }

    /** Drops every line carrying the key, keeping the file's mode */
    fun removeScript(keyBody: String): String = """
        f="${'$'}HOME/.ssh/authorized_keys"
        [ -f "${'$'}f" ] || exit 0
        t=${'$'}(mktemp "${'$'}f.XXXXXX") || exit 1
        grep -vF '$keyBody' "${'$'}f" > "${'$'}t" || true
        chmod 600 "${'$'}t"
        mv "${'$'}t" "${'$'}f"
        ! grep -qF '$keyBody' "${'$'}f"
    """.trimIndent()

    /** Machines behind other machines come first */
    fun removalOrder(nodes: List<DeploymentNode>): List<DeploymentNode> {
        val byID = nodes.associateBy { it.id }
        fun depth(node: DeploymentNode): Int {
            var hops = 0
            var next = node.routedThrough
            val seen = mutableSetOf(node.id)
            while (next != null && seen.add(next)) {
                val parent = byID[next] ?: break
                hops += 1
                next = parent.routedThrough
            }
            return hops
        }
        return nodes.withIndex()
            .sortedWith(compareByDescending<IndexedValue<DeploymentNode>> { depth(it.value) }.thenBy { it.index })
            .map { it.value }
    }
}
