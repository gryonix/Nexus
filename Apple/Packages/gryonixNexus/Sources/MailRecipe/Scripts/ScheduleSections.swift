enum ScheduleSections {
    static let grammar = "<off|every:<n><h|d>@<HH:MM>>"

    static let argumentComment = #"""
      # <schedule> is `off` or `every:<n><unit>@<HH:MM>` — the interval and
      # the time of day the user picked. Parsed here rather than taking a
      # raw OnCalendar expression: the wrapper is whitelisted in sudoers,
      # so it must not accept arbitrary systemd input from the client.
    """#

    static let parser = #"""
      local oncal=""
      case "$schedule" in
        off) ;;
        every:*)
          local spec="${schedule#every:}"
          local every="${spec%@*}" at="${spec#*@}"
          local n="${every%[hd]}" unit="${every##*[0-9]}"
          case "$n" in
            ''|*[!0-9]*) echo "invalid interval: ${every}" >&2; exit 2 ;;
          esac
          [ "$n" -ge 1 ] || { echo "invalid interval: ${every}" >&2; exit 2; }
          case "$at" in
            [0-2][0-9]:[0-5][0-9]) ;;
            *) echo "invalid time: ${at}" >&2; exit 2 ;;
          esac
          [ "${at%%:*}" -le 23 ] || { echo "invalid time: ${at}" >&2; exit 2; }
          case "$unit" in
            h)
              # Every n hours, aligned to the chosen minute.
              if [ "$n" -ge 24 ]; then
                oncal="*-*-* ${at}:00"
              else
                oncal="*-*-* 00/${n}:${at#*:}:00"
              fi
              ;;
            d)
              # Every n days at the chosen time. systemd has no "every n
              # days" for n > 1, so those run daily-aligned on a day step.
              if [ "$n" -le 1 ]; then
                oncal="*-*-* ${at}:00"
              else
                oncal="*-*-01/${n} ${at}:00"
              fi
              ;;
            *) echo "invalid interval unit: ${every}" >&2; exit 2 ;;
          esac
          ;;
        *) echo "unsupported schedule: ${schedule}" >&2; exit 2 ;;
      esac
    """#

    /// Writes the timer unit and (de)activates it from `$schedule`/`$oncal`
    static func timerActivation(timerName: String, description: String,
                                delimiter: String) -> String {
        #"""
          if [ "$schedule" = "off" ]; then
            systemctl disable --now '\#(timerName)' >/dev/null 2>&1 || true
          else
            mkdir -p /etc/systemd/system
            cat > /etc/systemd/system/\#(timerName) <<\#(delimiter)
        [Unit]
        Description=\#(description)
        [Timer]
        OnCalendar=$oncal
        # Servers are not up 24/7 — a missed window must still run.
        Persistent=true
        # Small jitter only: the user picked a specific time, so the run must
        # not wander an hour away from it.
        RandomizedDelaySec=5m
        [Install]
        WantedBy=timers.target
        \#(delimiter)
            systemctl daemon-reload
            # A bad OnCalendar would leave the timer permanently inactive —
            # catch it here, while the app is still listening. Only when the
            # tool is actually present: its ABSENCE must not reject a schedule
            # that is fine (minimal images ship without systemd-analyze).
            if command -v systemd-analyze >/dev/null 2>&1; then
              if ! systemd-analyze calendar "$oncal" >/dev/null 2>&1; then
                echo "invalid schedule expression: ${oncal}" >&2; exit 2
              fi
            fi
            systemctl enable --now '\#(timerName)' >/dev/null 2>&1 || true
          fi
        """#
    }
}
