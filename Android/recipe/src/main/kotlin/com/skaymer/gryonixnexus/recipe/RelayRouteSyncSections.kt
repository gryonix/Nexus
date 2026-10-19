package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.core.WireGuardDefaults

internal object RelayRouteSyncSections {
    const val SCRIPT_PATH = "/opt/gryonixnexus-relay-route-sync.sh"
    const val SERVICE_UNIT = "gryonixnexus-relay-route-sync.service"
    const val TIMER_UNIT = "gryonixnexus-relay-route-sync.timer"

    const val ROUTE_TABLE = "100"

    const val FW_MARK = "0x1"

    private val wgIF: String get() = WireGuardDefaults.INTERFACE_NAME

    private val script: String
        get() = """
        #!/bin/bash
        # Managed by gryonixNexus — mirrors the main routing table's
        # locally-connected routes (Docker's bridges included) into a
        # policy-routing table that defaults via the tunnel, so a relayed
        # connection's reply — marked by nftables' prerouting chain — finds
        # its way back through $wgIF instead of the home ISP's default
        # gateway, while traffic actually destined for a container (the other
        # leg of the very same DNATed connection) still reaches the local
        # bridge. Re-run periodically (see the .timer unit): Docker creates
        # and destroys bridges as services are installed and removed.
        set -euo pipefail

        TABLE=$ROUTE_TABLE
        MARK=$FW_MARK

        ip rule del fwmark "${SH}MARK" table "${SH}TABLE" 2>/dev/null || true
        ip rule add fwmark "${SH}MARK" table "${SH}TABLE"

        ip route flush table "${SH}TABLE" 2>/dev/null || true
        # Mirror every locally-connected route (Docker's bridges included) so
        # relayed traffic whose real destination is a container keeps going
        # there; only a genuine default-route destination falls to the
        # tunnel. Word-splitting on ${SH}route is deliberate: each line from
        # `ip route show` is a multi-field route spec that `ip route add`
        # expects as separate arguments. Gateway routes stay out: a
        # host route to the relay would pull its own sites off the tunnel.
        while IFS= read -r route; do
          [ -n "${SH}route" ] || continue
          # shellcheck disable=SC2086
          ip route add ${SH}route table "${SH}TABLE" 2>/dev/null || true
        done < <(ip route show table main scope link || true)

        ip route add default dev "$wgIF" table "${SH}TABLE"
        """.trimIndent()

    private val serviceUnitContents: String
        get() = """
        [Unit]
        Description=gryonixNexus relay route sync (mirrors Docker's bridges into the tunnel policy-routing table)
        After=wg-quick@$wgIF.service docker.service
        Requires=wg-quick@$wgIF.service

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
        ExecStart=$SCRIPT_PATH

        [Install]
        WantedBy=multi-user.target
        """.trimIndent()

    private val timerUnitContents: String
        get() = """
        [Unit]
        Description=Periodic gryonixNexus relay route sync

        [Timer]
        # Docker bridges come and go as services are installed/removed; this
        # is the only thing that notices without a re-run of setup.
        OnUnitActiveSec=2min
        Persistent=true

        [Install]
        WantedBy=timers.target
        """.trimIndent()

    fun install(): String = """
        log "Relay route sync: $SCRIPT_PATH"
        @SCRIPT@
        chmod 700 $SCRIPT_PATH
        @SERVICE@
        @TIMER@
        systemctl daemon-reload
        systemctl enable --now $TIMER_UNIT >/dev/null 2>&1 || true
        systemctl start $SERVICE_UNIT || true
        """.trimIndent().embedding(
        "SCRIPT" to BashSections.writeFile(SCRIPT_PATH, script, "EOF_ROUTESYNC"),
        "SERVICE" to BashSections.writeFile("/etc/systemd/system/$SERVICE_UNIT",
                                            serviceUnitContents, "EOF_ROUTESYNC_SVC"),
        "TIMER" to BashSections.writeFile("/etc/systemd/system/$TIMER_UNIT",
                                          timerUnitContents, "EOF_ROUTESYNC_TIMER")
    )

    /** Removal for the home host's uninstall wrapper — scenario B only */
    fun uninstallLines(indent: String): List<String> = listOf(
        "$indent# Policy routing that sends relayed replies back through the",
        "$indent# tunnel — armed by install(), re-synced by its own timer.",
        "${indent}systemctl disable --now '$TIMER_UNIT' '$SERVICE_UNIT' >/dev/null 2>&1 || true",
        "${indent}rm -f /etc/systemd/system/$TIMER_UNIT /etc/systemd/system/$SERVICE_UNIT",
        "${indent}systemctl daemon-reload || true",
        "${indent}rm -f '$SCRIPT_PATH'",
        "${indent}ip rule del fwmark '$FW_MARK' table '$ROUTE_TABLE' 2>/dev/null || true",
        "${indent}ip route flush table '$ROUTE_TABLE' 2>/dev/null || true"
    )
}
