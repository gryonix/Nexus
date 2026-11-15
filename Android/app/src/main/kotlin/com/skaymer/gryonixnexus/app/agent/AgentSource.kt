package com.skaymer.gryonixnexus.app.agent

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Where an agent install or update takes its sources from */
enum class AgentSource(val raw: String, val branch: String?) {
    APP("app", null),
    REPOSITORY_MAIN("repositoryMain", "main"),
    REPOSITORY_BETA("repositoryBeta", "beta"),
    REPOSITORY_WIP("repositoryWip", "wip");

    /** The agent version on this branch, read from github.com */
    suspend fun branchVersion(): String? {
        val branch = branch ?: return null
        return withContext(Dispatchers.IO) {
            runCatching {
                val url = URL("https://raw.githubusercontent.com/$REPOSITORY/$branch/Agent/gryonixnexusd/Cargo.toml")
                val connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 15_000
                connection.readTimeout = 15_000
                connection.useCaches = false
                try {
                    if (connection.responseCode != 200) null
                    else crateVersion(connection.inputStream.bufferedReader().readText())
                } finally {
                    connection.disconnect()
                }
            }.getOrNull()
        }
    }

    /** The version an update from this source installs */
    suspend fun offeredVersion(shipped: String): String = branchVersion() ?: shipped

    /** Fetches the branch where the wrapper looks */
    fun fetchScript(archivePath: String): String? {
        val branch = branch ?: return null
        val url = "https://codeload.github.com/$REPOSITORY/tar.gz/refs/heads/$branch"
        return """
            set -eu
            WORK="${'$'}(mktemp -d)"
            trap 'rm -rf "${'$'}WORK"' EXIT
            command -v curl >/dev/null 2>&1 || { echo 'this server has no curl' >&2; exit 1; }
            # The status code, because GitHub hides a private repository behind 404.
            CODE="${'$'}(curl -sSL -o "${'$'}WORK/repo.tar.gz" -w '%{http_code}' '$url' || echo 000)"
            case "${'$'}CODE" in
              200) ;;
              404) echo 'github.com/$REPOSITORY answered 404 for the branch $branch: this server reads it without credentials, so it has to be a public repository and the branch has to exist. Make the repository public, or install the agent from the app.' >&2; exit 1 ;;
              000) echo 'this server could not reach github.com at all' >&2; exit 1 ;;
              *) echo "github.com/$REPOSITORY answered ${'$'}CODE for the branch $branch" >&2; exit 1 ;;
            esac
            mkdir -p "${'$'}WORK/repo"
            tar -xzf "${'$'}WORK/repo.tar.gz" -C "${'$'}WORK/repo"
            ROOT="${'$'}(find "${'$'}WORK/repo" -mindepth 1 -maxdepth 1 -type d | head -1)"
            [ -d "${'$'}ROOT/Agent/gryonixnexusd" ] || { echo 'that branch carries no agent sources' >&2; exit 1; }
            rm -rf "${'$'}ROOT/Agent/gryonixnexusd/target"
            tar -czf ${singleQuoted(archivePath)} -C "${'$'}ROOT" Agent
            grep -m1 '^version' "${'$'}ROOT/Agent/gryonixnexusd/Cargo.toml" || true
        """.trimIndent()
    }

    companion object {
        /** The public repository the branches are read from */
        const val REPOSITORY = "gryonix/nexus-agent"

        /** The same key as on Apple */
        const val SETTINGS_KEY = "agent.source"

        /** Only these names ever reach a shell command */
        fun named(raw: String?): AgentSource = entries.firstOrNull { it.raw == raw } ?: APP

        private fun singleQuoted(value: String): String = "'" + value.replace("'", "'\\''") + "'"

        /** The first `version = "…"` line of a Cargo manifest */
        fun crateVersion(manifest: String): String? {
            val prefix = "version = \""
            val line = manifest.lineSequence().firstOrNull { it.startsWith(prefix) } ?: return null
            return line.removePrefix(prefix).takeWhile { it != '"' }.ifEmpty { null }
        }
    }
}
