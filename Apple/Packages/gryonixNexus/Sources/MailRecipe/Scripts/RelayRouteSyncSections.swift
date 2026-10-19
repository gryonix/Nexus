import gryonixNexusCore

enum RelayRouteSyncSections {
    static let scriptPath = "/opt/gryonixnexus-relay-route-sync.sh"
    static let serviceUnit = "gryonixnexus-relay-route-sync.service"
    static let timerUnit = "gryonixnexus-relay-route-sync.timer"
    static let routeTable = "100"
    static let fwMark = "0x1"

    private static var wgIF: String { WireGuardDefaults.interfaceName }

    private static var script: String {
        #"""
        #!/bin/bash
        # Managed by gryonixNexus — mirrors the main routing table's
        # locally-connected routes (Docker's bridges included) into a
        # policy-routing table that defaults via the tunnel, so a relayed
        # connection's reply — marked by nftables' prerouting chain — finds
        # its way back through \#(wgIF) instead of the home ISP's default
        # gateway, while traffic actually destined for a container (the other
        # leg of the very same DNATed connection) still reaches the local
        # bridge. Re-run periodically (see the .timer unit): Docker creates
        # and destroys bridges as services are installed and removed.
        set -euo pipefail

        TABLE=\#(routeTable)
        MARK=\#(fwMark)

        ip rule del fwmark "$MARK" table "$TABLE" 2>/dev/null || true
        ip rule add fwmark "$MARK" table "$TABLE"

        ip route flush table "$TABLE" 2>/dev/null || true
        # Mirror every locally-connected route (Docker's bridges included) so
        # relayed traffic whose real destination is a container keeps going
        # there; only a genuine default-route destination falls to the
        # tunnel. Word-splitting on $route is deliberate: each line from
        # `ip route show` is a multi-field route spec that `ip route add`
        # expects as separate arguments. Gateway routes stay out: a
        # host route to the relay would pull its own sites off the tunnel.
        while IFS= read -r route; do
          [ -n "$route" ] || continue
          # shellcheck disable=SC2086
          ip route add $route table "$TABLE" 2>/dev/null || true
        done < <(ip route show table main scope link || true)

        ip route add default dev "\#(wgIF)" table "$TABLE"
        """#
    }

    private static var serviceUnitContents: String {
        #"""
        [Unit]
        Description=gryonixNexus relay route sync (mirrors Docker's bridges into the tunnel policy-routing table)
        After=wg-quick@\#(wgIF).service docker.service
        Requires=wg-quick@\#(wgIF).service

        [Service]
        Type=oneshot
        # No RemainAfterExit: this unit is re-triggered by its own timer every
        # 2 minutes, and a oneshot service that stays "active (exited)" after
        # its first run does not actually re-execute on a later `start` — the
        # manager sees it's already active and treats the job as redundant.
        # The timer's second tick fired (LastTriggerUSec
        # advanced) but the script never ran a second time, and a docker
        # bridge created between runs stayed unmirrored — exactly the failure
        # this timer exists to prevent.
        ExecStart=\#(scriptPath)

        [Install]
        WantedBy=multi-user.target
        """#
    }

    private static var timerUnitContents: String {
        #"""
        [Unit]
        Description=Periodic gryonixNexus relay route sync

        [Timer]
        # Docker bridges come and go as services are installed/removed; this
        # is the only thing that notices without a re-run of setup.
        OnUnitActiveSec=2min
        Persistent=true

        [Install]
        WantedBy=timers.target
        """#
    }

    static func install() -> String {
        #"""
        log "Relay route sync: \#(scriptPath)"
        \#(BashSections.writeFile(path: scriptPath, contents: script, delimiter: "EOF_ROUTESYNC"))
        chmod 700 \#(scriptPath)
        \#(BashSections.writeFile(path: "/etc/systemd/system/\(serviceUnit)", contents: serviceUnitContents, delimiter: "EOF_ROUTESYNC_SVC"))
        \#(BashSections.writeFile(path: "/etc/systemd/system/\(timerUnit)", contents: timerUnitContents, delimiter: "EOF_ROUTESYNC_TIMER"))
        systemctl daemon-reload
        systemctl enable --now \#(timerUnit) >/dev/null 2>&1 || true
        systemctl start \#(serviceUnit) || true
        """#
    }

    /// Removal for the home host's uninstall wrapper — scenario B only
    static func uninstallLines(indent: String) -> [String] {
        [
            "\(indent)# Policy routing that sends relayed replies back through the",
            "\(indent)# tunnel — armed by install(), re-synced by its own timer.",
            "\(indent)systemctl disable --now '\(timerUnit)' '\(serviceUnit)' >/dev/null 2>&1 || true",
            "\(indent)rm -f /etc/systemd/system/\(timerUnit) /etc/systemd/system/\(serviceUnit)",
            "\(indent)systemctl daemon-reload || true",
            "\(indent)rm -f '\(scriptPath)'",
            "\(indent)ip rule del fwmark '\(fwMark)' table '\(routeTable)' 2>/dev/null || true",
            "\(indent)ip route flush table '\(routeTable)' 2>/dev/null || true"
        ]
    }
}
