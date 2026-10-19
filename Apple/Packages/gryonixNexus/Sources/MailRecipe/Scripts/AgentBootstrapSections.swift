import Foundation

public enum AgentBootstrapSections {
    public static let scriptPath = "/opt/gryonixnexus-agent-bootstrap.sh"
    public static let agentBinaryPath = "/usr/local/bin/gryonixnexusd"
    public static let bridgeSudoersTarget = "\(agentBinaryPath) bridge"
    public static let pairCodeSudoersTarget = "\(agentBinaryPath) pair-code"
    /// What the app actually runs
    public static let bridgeCommand = "sudo -n \(bridgeSudoersTarget)"
    public static let archiveName = "gryonixnexus-agent-src.tar.gz"
    /// Asks the bootstrap to rebuild even the same version
    public static let reinstallMarkerName = ".gryonixnexus-agent-reinstall"
    public static let unpackRoot = "/opt/gryonixnexus-agent-src"

    /// The agent version the SOURCES IN THIS APP build to
    public static let bundledVersion = "26.10.20"

    public static func wrapper(user: String) -> String {
        #"""
        log "Agent bootstrap wrapper"
        cat > '\#(scriptPath)' <<'EOF_AGENT_BOOTSTRAP'
        \#(wrapperScript(archivePath: archivePath(user: user)))
        EOF_AGENT_BOOTSTRAP
        chown root:root '\#(scriptPath)'
        chmod 700 '\#(scriptPath)'
        """#
    }

    /// The wrapper's own text, with nothing around it
    public static func wrapperScript(archivePath: String) -> String {
        #"""
        #!/bin/bash
        # Managed by gryonixNexus — installs or updates the control-plane agent
        # from the archive the app uploaded into the control user's home.
        #
        # No arguments, deliberately: this runs under sudo, and an argument is
        # an argument that reached root.
        set -euo pipefail
        ARCHIVE='\#(archivePath)'
        UNPACK='\#(unpackRoot)'

        # The sudo caller's own upload wins; sudo sets SUDO_USER
        caller_home="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
        if [ -n "$caller_home" ] && [ -s "$caller_home/\#(archiveName)" ]; then
          ARCHIVE="$caller_home/\#(archiveName)"
        fi

        [ -s "$ARCHIVE" ] || { echo "no agent sources uploaded ($ARCHIVE)" >&2; exit 1; }

        # --no-same-owner: the archive is written on a Mac, so its uids mean
        # nothing here, and tar honouring them fails in ways that read like a
        # corrupt archive.
        rm -rf "$UNPACK"
        install -d -m 700 "$UNPACK"
        tar -xzf "$ARCHIVE" -C "$UNPACK" --no-same-owner
        rm -f "$ARCHIVE"

        [ -x "$UNPACK/Agent/bootstrap/install-agent.sh" ] \
          || { echo "the uploaded archive carries no bootstrap script" >&2; exit 1; }
        cd "$UNPACK/Agent"
        exec bash bootstrap/install-agent.sh
        """#
    }

    /// The upload target, in the control user's own home
    public static func archivePath(user: String) -> String {
        user == "root" ? "/root/\(archiveName)" : "/home/\(user)/\(archiveName)"
    }
}
