package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.SH

object AgentBootstrapSections {
    const val SCRIPT_PATH = "/opt/gryonixnexus-agent-bootstrap.sh"

    /** Where the agent's own bootstrap puts the built binary */
    const val AGENT_BINARY_PATH = "/usr/local/bin/gryonixnexusd"

    /** Which agent this app carries */
    const val BUNDLED_VERSION = "26.10.20"

    const val BRIDGE_SUDOERS_TARGET = "$AGENT_BINARY_PATH bridge"

    const val PAIR_CODE_SUDOERS_TARGET = "$AGENT_BINARY_PATH pair-code"

    /** What the app actually runs */
    const val BRIDGE_COMMAND = "sudo -n $BRIDGE_SUDOERS_TARGET"

    const val ARCHIVE_NAME = "gryonixnexus-agent-src.tar.gz"

    /** Asks the bootstrap to rebuild even the same version */
    const val REINSTALL_MARKER_NAME = ".gryonixnexus-agent-reinstall"
    const val UNPACK_ROOT = "/opt/gryonixnexus-agent-src"

    fun wrapper(user: String): String = """
        log "Agent bootstrap wrapper"
        cat > '$SCRIPT_PATH' <<'EOF_AGENT_BOOTSTRAP'
        @WRAPPER@
        EOF_AGENT_BOOTSTRAP
        chown root:root '$SCRIPT_PATH'
        chmod 700 '$SCRIPT_PATH'
        """.trimIndent().replace("@WRAPPER@", wrapperScript(archivePath(user)))

    fun wrapperScript(archivePath: String): String = """
        #!/bin/bash
        # Managed by gryonixNexus — installs or updates the control-plane agent
        # from the archive the app uploaded into the control user's home.
        #
        # No arguments, deliberately: this runs under sudo, and an argument is
        # an argument that reached root.
        set -euo pipefail
        ARCHIVE='@ARCHIVE@'
        UNPACK='$UNPACK_ROOT'

        # The sudo caller's own upload wins; sudo sets SUDO_USER
        caller_home="${SH}(getent passwd "${SH}{SUDO_USER:-root}" | cut -d: -f6)"
        if [ -n "${SH}caller_home" ] && [ -s "${SH}caller_home/$ARCHIVE_NAME" ]; then
          ARCHIVE="${SH}caller_home/$ARCHIVE_NAME"
        fi

        [ -s "${SH}ARCHIVE" ] || { echo "no agent sources uploaded (${SH}ARCHIVE)" >&2; exit 1; }

        # --no-same-owner: the archive is written on a Mac, so its uids mean
        # nothing here, and tar honouring them fails in ways that read like a
        # corrupt archive.
        rm -rf "${SH}UNPACK"
        install -d -m 700 "${SH}UNPACK"
        tar -xzf "${SH}ARCHIVE" -C "${SH}UNPACK" --no-same-owner
        rm -f "${SH}ARCHIVE"

        [ -x "${SH}UNPACK/Agent/bootstrap/install-agent.sh" ] \
          || { echo "the uploaded archive carries no bootstrap script" >&2; exit 1; }
        cd "${SH}UNPACK/Agent"
        exec bash bootstrap/install-agent.sh
        """.trimIndent().replace("@ARCHIVE@", archivePath)

    /** The upload target, in the control user's own home */
    fun archivePath(user: String): String =
        if (user == "root") "/root/$ARCHIVE_NAME" else "/home/$user/$ARCHIVE_NAME"
}
