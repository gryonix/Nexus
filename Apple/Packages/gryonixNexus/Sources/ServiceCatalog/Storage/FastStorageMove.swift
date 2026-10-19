import Foundation

/// Moves live databases and caches onto a fast disk
public struct FastStorageMove: Sendable, Hashable {
    /// One compose project and its hot directories
    public struct Project: Sendable, Hashable {
        public let directory: String
        public let hotPaths: [String]

        public init(directory: String, hotPaths: [String]) {
            self.directory = directory
            self.hotPaths = hotPaths
        }
    }

    public let target: FastStoragePlan.Target
    public let projects: [Project]

    public static let doneMarker = "GRYONIXNEXUS_FAST_MOVE_DONE"
    public static let composeMarker = "### "

    public init(target: FastStoragePlan.Target, projects: [Project]) {
        self.target = target
        self.projects = projects
    }

    /// Prints each compose file after a header line
    public static let probeCommand =
        "for f in $(ls -d /opt/*/docker-compose.y*ml /opt/*/compose.y*ml /srv/*/docker-compose.y*ml 2>/dev/null); "
        + "do echo \"\(composeMarker)$f\"; cat \"$f\"; echo; done; "
        + "mountpoint -q \(FastStoragePlan.mountPoint) && echo \"\(mountedMarker)\" || true; "
        + "awk '$3 == \"none\" && $1 ~ /gryonixnexus-fast\\/binds/ {print \"\(boundMarker) \" $2}' /etc/fstab"

    static let mountedMarker = "GRYONIXNEXUS_FAST_MOUNTED"
    static let boundMarker = "GRYONIXNEXUS_FAST_BOUND"

    /// Folders already living on the fast disk
    public static func bound(inProbe text: String) -> Set<String> {
        let prefix = boundMarker + " "
        return Set(text.split(separator: "\n").filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) })
    }

    /// Projects with hot directories, read from the probe
    public static func projects(inProbe text: String) -> [Project] {
        var result: [Project] = []
        var file: String?
        var body = ""
        func flush() {
            guard let file else { return }
            let hot = FastStoragePlan.hotPaths(inText: body)
            let directory = (file as NSString).deletingLastPathComponent
            if !hot.isEmpty { result.append(Project(directory: directory, hotPaths: hot)) }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(composeMarker) {
                flush()
                file = String(line.dropFirst(composeMarker.count))
                body = ""
            } else {
                body += line + "\n"
            }
        }
        flush()
        return result
    }

    public static func isMounted(inProbe text: String) -> Bool {
        text.split(separator: "\n").contains { $0 == mountedMarker }
    }

    public var root: String { FastStoragePlan(target: target, hotPaths: []).root }

    public func script() -> String {
        var lines = ["#!/bin/bash", "set -euo pipefail", "FAST=\(ShellQuoting.singleQuoted(root))"]
        switch target {
        case .device(let path): lines += FastStoragePlan.formatLines(path)
        case .folder: lines.append("install -d \"$FAST\"")
        }
        lines += Self.rsyncLines() + Self.moveFunctions()
        for project in projects {
            let dirs = project.hotPaths.map(ShellQuoting.singleQuoted).joined(separator: " ")
            lines.append("move_project \(ShellQuoting.singleQuoted(project.directory)) \(dirs) || FAILED=1")
        }
        lines += ["[ \"${FAILED:-0}\" = 0 ] || exit 4", "echo \(Self.doneMarker)"]
        return lines.joined(separator: "\n") + "\n"
    }

    static func rsyncLines() -> [String] {
        [
            "if ! command -v rsync >/dev/null 2>&1; then",
            "  export DEBIAN_FRONTEND=noninteractive",
            "  \(Apt.quiet) install -y -qq rsync >/dev/null",
            "fi",
        ]
    }

    /// Stop, copy, keep the old copy aside, bind, start again
    static func moveFunctions() -> [String] {
        [
            "move_dir() {",
            "  local target=\"$1\" source=\"$FAST/binds$1\" old=\"$1.before-cache\"",
            "  if mountpoint -q \"$target\"; then echo \"$target is already on the fast disk\"; return 0; fi",
            "  if [ ! -d \"$target\" ]; then echo \"$target does not exist, skipped\"; return 0; fi",
            "  echo \"Moving $target\"",
            "  install -d \"$source\" || return 1",
            "  rsync -aHAX --delete \"$target/\" \"$source/\" || return 1",
            "  if [ -e \"$old\" ]; then old=\"$old.$(date +%s)\"; fi",
            "  mv \"$target\" \"$old\" || return 1",
            "  install -d \"$target\" || return 1",
            "  " + FastStoragePlan.bindLine(source: "$source", target: "$target") + " || return 1",
            "  mount \"$target\" || return 1",
            "}",
            "move_project() {",
            "  local project=\"$1\" rc=0 todo=0",
            "  shift",
            "  for dir in \"$@\"; do mountpoint -q \"$dir\" || todo=1; done",
            "  if [ \"$todo\" = 0 ]; then echo \"$project is already on the fast disk\"; return 0; fi",
            "  (cd \"$project\" && docker compose stop) || return 1",
            "  for dir in \"$@\"; do move_dir \"$dir\" || rc=1; done",
            "  (cd \"$project\" && docker compose start) || rc=1",
            "  return $rc",
            "}",
        ]
    }
}
