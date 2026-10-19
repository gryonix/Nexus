enum LockSections {
    /// Where per-service lock files live
    static let directory = "/var/lib/gryonixnexus/locks"

    static let busyExitCode = "75"

    static let helper = #"""
    GD_LOCK_BUSY=\#(busyExitCode)

    gd_with_lock() {
      local id="$1"
      shift
      install -d -m 700 '\#(directory)'
      local fd
      exec {fd}>"\#(directory)/$id.lock"
      if ! flock -n "$fd"; then
        echo "$id: another backup or update for this service is already running, skipping" >&2
        return "$GD_LOCK_BUSY"
      fi
      "$@"
    }
    """#
}
