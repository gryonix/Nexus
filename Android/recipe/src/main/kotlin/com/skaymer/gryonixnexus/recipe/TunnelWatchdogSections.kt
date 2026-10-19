package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.core.WireGuardDefaults

/** Restarts the home tunnel when its handshake goes stale */
internal object TunnelWatchdogSections {
    const val SCRIPT_PATH = "/opt/gryonixnexus-tunnel-watchdog.sh"
    const val SERVICE_UNIT = "gryonixnexus-tunnel-watchdog.service"
    const val TIMER_UNIT = "gryonixnexus-tunnel-watchdog.timer"
    const val STALE_SECONDS = 300

    private val wgIF: String get() = WireGuardDefaults.INTERFACE_NAME

    private val script: String
        get() = """
        #!/bin/bash
        # Managed by gryonixNexus — restarts the tunnel after a silent spell.
        set -euo pipefail
        unit="wg-quick@$wgIF"
        systemctl is-active --quiet "${SH}unit" || exit 0

        uptime_s="${SH}(cut -d. -f1 /proc/uptime)"
        started_us="${SH}(systemctl show -p ActiveEnterTimestampMonotonic --value "${SH}unit")"
        running_for=${SH}(( uptime_s - ${SH}{started_us:-0} / 1000000 ))

        handshake="${SH}(wg show $wgIF latest-handshakes 2>/dev/null | awk 'NR==1{print ${SH}2}' || true)"
        if [ "${SH}{handshake:-0}" -gt 0 ]; then
          quiet_for=${SH}(( ${SH}(date +%s) - handshake ))
        else
          quiet_for=${SH}running_for
        fi

        if [ "${SH}running_for" -gt $STALE_SECONDS ] && [ "${SH}quiet_for" -gt $STALE_SECONDS ]; then
          logger -t gryonixnexus-tunnel "no handshake for ${SH}{quiet_for}s, restarting ${SH}unit"
          systemctl restart "${SH}unit"
          systemctl start ${RelayRouteSyncSections.SERVICE_UNIT} || true
        fi
        """.trimIndent()

    private val serviceUnitContents: String
        get() = """
        [Unit]
        Description=gryonixNexus tunnel watchdog (restarts a tunnel with a stale handshake)
        After=wg-quick@$wgIF.service

        [Service]
        Type=oneshot
        ExecStart=$SCRIPT_PATH
        """.trimIndent()

    private val timerUnitContents: String
        get() = """
        [Unit]
        Description=Periodic gryonixNexus tunnel watchdog

        [Timer]
        OnBootSec=2min
        OnUnitActiveSec=1min

        [Install]
        WantedBy=timers.target
        """.trimIndent()

    fun install(): String = """
        log "Tunnel watchdog: $SCRIPT_PATH"
        @SCRIPT@
        chmod 700 $SCRIPT_PATH
        @SERVICE@
        @TIMER@
        systemctl daemon-reload
        systemctl enable --now $TIMER_UNIT >/dev/null 2>&1 || true
        """.trimIndent().embedding(
        "SCRIPT" to BashSections.writeFile(SCRIPT_PATH, script, "EOF_WATCHDOG"),
        "SERVICE" to BashSections.writeFile("/etc/systemd/system/$SERVICE_UNIT",
                                            serviceUnitContents, "EOF_WATCHDOG_SVC"),
        "TIMER" to BashSections.writeFile("/etc/systemd/system/$TIMER_UNIT",
                                          timerUnitContents, "EOF_WATCHDOG_TIMER")
    )

    /** Removal lines for the home host's uninstall wrapper */
    fun uninstallLines(indent: String): List<String> = listOf(
        "${indent}systemctl disable --now '$TIMER_UNIT' '$SERVICE_UNIT' >/dev/null 2>&1 || true",
        "${indent}rm -f /etc/systemd/system/$TIMER_UNIT /etc/systemd/system/$SERVICE_UNIT '$SCRIPT_PATH'"
    )
}
