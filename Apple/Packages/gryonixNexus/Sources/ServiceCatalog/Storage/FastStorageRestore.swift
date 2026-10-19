import Foundation

/// Returns moved folders or deletes their old copies
public enum FastStorageRestore {
    public static let doneMarker = "GRYONIXNEXUS_FAST_RESTORE_DONE"
    public static let cleanupDoneMarker = "GRYONIXNEXUS_FAST_CLEANUP_DONE"

    /// Stop, copy the current data back, unbind, start again
    public static func script(projects: [FastStorageMove.Project]) -> String {
        var lines = ["#!/bin/bash", "set -euo pipefail"] + FastStorageMove.rsyncLines() + functions()
        for project in projects {
            let dirs = project.hotPaths.map(ShellQuoting.singleQuoted).joined(separator: " ")
            lines.append("restore_project \(ShellQuoting.singleQuoted(project.directory)) \(dirs) || FAILED=1")
        }
        lines += ["[ \"${FAILED:-0}\" = 0 ] || exit 4", "echo \(doneMarker)"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Deletes the copies a move left beside each folder
    public static func cleanupScript(paths: [String]) -> String {
        var lines = ["#!/bin/bash", "set -euo pipefail"]
        for path in paths {
            let old = ShellQuoting.singleQuoted(path + ".before-cache")
            lines.append("for old in \(old) \(old).*; do [ -d \"$old\" ] || continue; rm -rf -- \"$old\"; echo \"removed $old\"; done")
        }
        lines.append("echo \(cleanupDoneMarker)")
        return lines.joined(separator: "\n") + "\n"
    }

    static func functions() -> [String] {
        [
            "bound_source() {",
            "  awk -v t=\"$1\" '$2 == t && $3 == \"none\" {print $1; exit}' /etc/fstab",
            "}",
            "restore_dir() {",
            "  local target=\"$1\" source",
            "  source=\"$(bound_source \"$target\")\"",
            "  if [ -z \"$source\" ]; then echo \"$target is not on the fast disk\"; return 0; fi",
            "  echo \"Bringing back $target\"",
            "  if mountpoint -q \"$target\"; then umount \"$target\" || return 1; fi",
            "  rsync -aHAX --delete \"$source/\" \"$target/\" || return 1",
            "  awk -v t=\"$target\" '!($2 == t && $3 == \"none\")' /etc/fstab > /etc/fstab.gryonixnexus || return 1",
            "  cat /etc/fstab.gryonixnexus > /etc/fstab && rm -f /etc/fstab.gryonixnexus || return 1",
            "}",
            "restore_project() {",
            "  local project=\"$1\" rc=0 todo=0",
            "  shift",
            "  for dir in \"$@\"; do [ -n \"$(bound_source \"$dir\")\" ] && todo=1; done",
            "  if [ \"$todo\" = 0 ]; then echo \"$project is on the system disk\"; return 0; fi",
            "  (cd \"$project\" && docker compose stop) || return 1",
            "  for dir in \"$@\"; do restore_dir \"$dir\" || rc=1; done",
            "  (cd \"$project\" && docker compose start) || rc=1",
            "  return $rc",
            "}",
        ]
    }
}
