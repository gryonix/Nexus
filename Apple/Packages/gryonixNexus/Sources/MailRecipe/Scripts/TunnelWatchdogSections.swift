import gryonixNexusCore

/// Restarts the home tunnel when its handshake goes stale
enum TunnelWatchdogSections {
    static let scriptPath = "/opt/gryonixnexus-tunnel-watchdog.sh"
    static let serviceUnit = "gryonixnexus-tunnel-watchdog.service"
    static let timerUnit = "gryonixnexus-tunnel-watchdog.timer"
    static let staleSeconds = 300

    private static var wgIF: String { WireGuardDefaults.interfaceName }

    private static var script: String {
        #"""
        #!/bin/bash
        # Managed by gryonixNexus — restarts the tunnel after a silent spell.
        set -euo pipefail
        unit="wg-quick@\#(wgIF)"
        systemctl is-active --quiet "$unit" || exit 0

        uptime_s="$(cut -d. -f1 /proc/uptime)"
        started_us="$(systemctl show -p ActiveEnterTimestampMonotonic --value "$unit")"
        running_for=$(( uptime_s - ${started_us:-0} / 1000000 ))

        handshake="$(wg show \#(wgIF) latest-handshakes 2>/dev/null | awk 'NR==1{print $2}' || true)"
        if [ "${handshake:-0}" -gt 0 ]; then
          quiet_for=$(( $(date +%s) - handshake ))
        else
          quiet_for=$running_for
        fi

        if [ "$running_for" -gt \#(staleSeconds) ] && [ "$quiet_for" -gt \#(staleSeconds) ]; then
          logger -t gryonixnexus-tunnel "no handshake for ${quiet_for}s, restarting $unit"
          systemctl restart "$unit"
          systemctl start \#(RelayRouteSyncSections.serviceUnit) || true
        fi
        """#
    }

    private static var serviceUnitContents: String {
        #"""
        [Unit]
        Description=gryonixNexus tunnel watchdog (restarts a tunnel with a stale handshake)
        After=wg-quick@\#(wgIF).service

        [Service]
        Type=oneshot
        ExecStart=\#(scriptPath)
        """#
    }

    private static var timerUnitContents: String {
        #"""
        [Unit]
        Description=Periodic gryonixNexus tunnel watchdog

        [Timer]
        OnBootSec=2min
        OnUnitActiveSec=1min

        [Install]
        WantedBy=timers.target
        """#
    }

    static func install() -> String {
        #"""
        log "Tunnel watchdog: \#(scriptPath)"
        \#(BashSections.writeFile(path: scriptPath, contents: script, delimiter: "EOF_WATCHDOG"))
        chmod 700 \#(scriptPath)
        \#(BashSections.writeFile(path: "/etc/systemd/system/\(serviceUnit)", contents: serviceUnitContents, delimiter: "EOF_WATCHDOG_SVC"))
        \#(BashSections.writeFile(path: "/etc/systemd/system/\(timerUnit)", contents: timerUnitContents, delimiter: "EOF_WATCHDOG_TIMER"))
        systemctl daemon-reload
        systemctl enable --now \#(timerUnit) >/dev/null 2>&1 || true
        """#
    }

    /// Removal lines for the home host's uninstall wrapper
    static func uninstallLines(indent: String) -> [String] {
        [
            "\(indent)systemctl disable --now '\(timerUnit)' '\(serviceUnit)' >/dev/null 2>&1 || true",
            "\(indent)rm -f /etc/systemd/system/\(timerUnit) /etc/systemd/system/\(serviceUnit) '\(scriptPath)'"
        ]
    }
}
