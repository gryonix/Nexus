package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.SH

internal object ScheduleSections {
    const val GRAMMAR = "<off|every:<n><h|d>@<HH:MM>>"

    val argumentComment = """
      # <schedule> is `off` or `every:<n><unit>@<HH:MM>` — the interval and
      # the time of day the user picked. Parsed here rather than taking a
      # raw OnCalendar expression: the wrapper is whitelisted in sudoers,
      # so it must not accept arbitrary systemd input from the client.
    """.trimIndent().prependIndent("  ")

    val parser = """
      local oncal=""
      case "${SH}schedule" in
        off) ;;
        every:*)
          local spec="${SH}{schedule#every:}"
          local every="${SH}{spec%@*}" at="${SH}{spec#*@}"
          local n="${SH}{every%[hd]}" unit="${SH}{every##*[0-9]}"
          case "${SH}n" in
            ''|*[!0-9]*) echo "invalid interval: ${SH}{every}" >&2; exit 2 ;;
          esac
          [ "${SH}n" -ge 1 ] || { echo "invalid interval: ${SH}{every}" >&2; exit 2; }
          case "${SH}at" in
            [0-2][0-9]:[0-5][0-9]) ;;
            *) echo "invalid time: ${SH}{at}" >&2; exit 2 ;;
          esac
          [ "${SH}{at%%:*}" -le 23 ] || { echo "invalid time: ${SH}{at}" >&2; exit 2; }
          case "${SH}unit" in
            h)
              # Every n hours, aligned to the chosen minute.
              if [ "${SH}n" -ge 24 ]; then
                oncal="*-*-* ${SH}{at}:00"
              else
                oncal="*-*-* 00/${SH}{n}:${SH}{at#*:}:00"
              fi
              ;;
            d)
              # Every n days at the chosen time. systemd has no "every n
              # days" for n > 1, so those run daily-aligned on a day step.
              if [ "${SH}n" -le 1 ]; then
                oncal="*-*-* ${SH}{at}:00"
              else
                oncal="*-*-01/${SH}{n} ${SH}{at}:00"
              fi
              ;;
            *) echo "invalid interval unit: ${SH}{every}" >&2; exit 2 ;;
          esac
          ;;
        *) echo "unsupported schedule: ${SH}{schedule}" >&2; exit 2 ;;
      esac
    """.trimIndent().prependIndent("  ")

    /** Writes the timer unit and (de)activates it from `${SH}schedule` / `${SH}oncal` */
    fun timerActivation(timerName: String, description: String, delimiter: String): String = """
      if [ "${SH}schedule" = "off" ]; then
        systemctl disable --now '$timerName' >/dev/null 2>&1 || true
      else
        mkdir -p /etc/systemd/system
        cat > /etc/systemd/system/$timerName <<$delimiter
    [Unit]
    Description=$description
    [Timer]
    OnCalendar=${SH}oncal
    # Servers are not up 24/7 — a missed window must still run.
    Persistent=true
    # Small jitter only: the user picked a specific time, so the run must
    # not wander an hour away from it.
    RandomizedDelaySec=5m
    [Install]
    WantedBy=timers.target
    $delimiter
        systemctl daemon-reload
        # A bad OnCalendar would leave the timer permanently inactive —
        # catch it here, while the app is still listening. Only when the
        # tool is actually present: its ABSENCE must not reject a schedule
        # that is fine (minimal images ship without systemd-analyze).
        if command -v systemd-analyze >/dev/null 2>&1; then
          if ! systemd-analyze calendar "${SH}oncal" >/dev/null 2>&1; then
            echo "invalid schedule expression: ${SH}{oncal}" >&2; exit 2
          fi
        fi
        systemctl enable --now '$timerName' >/dev/null 2>&1 || true
      fi
    """.trimIndent()
}
