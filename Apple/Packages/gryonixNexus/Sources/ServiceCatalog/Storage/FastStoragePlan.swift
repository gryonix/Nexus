/// Puts databases, caches and Docker's data on a fast disk
public struct FastStoragePlan: Sendable, Hashable {
    public enum Target: Sendable, Hashable {
        /// A whole device, formatted only if it has no filesystem
        case device(String)
        /// A folder on a filesystem that is already mounted
        case folder(on: String)
    }

    public let target: Target
    /// Service directories that move onto the fast disk
    public let hotPaths: [String]

    public static let mountPoint = "/srv/gryonixnexus-fast"
    public static let label = "gnx-fast"
    public static let doneMarker = "GRYONIXNEXUS_STORAGE_DONE"
    /// Last path components that hold databases or caches
    static let hotNames: Set<String> = ["db", "postgres", "redis", "cache", "ml-cache",
                                        "webmail-db", "storage"]

    public init(target: Target, hotPaths: [String]) {
        self.target = target
        self.hotPaths = hotPaths
    }

    public init(disk: ServerDisk, hotPaths: [String]) {
        let reusable = disk.isBlank || disk.isEarlierCache
        self.init(target: reusable ? .device(disk.path) : .folder(on: disk.dataMount ?? Self.mountPoint),
                  hotPaths: hotPaths)
    }

    /// Fast disks usable without losing anything on them
    public static func candidates(in hardware: ServerHardware) -> [ServerDisk] {
        hardware.disks.filter { disk in
            disk.isFast && !disk.isSystem && !disk.raidMember
                && (disk.isBlank || disk.dataMount != nil || disk.isEarlierCache)
        }
    }

    /// Hot bind-mounted directories named in the compose files
    public static func hotPaths(in composeFiles: [ComposeFile]) -> [String] {
        hotPaths(inText: composeFiles.map(\.composeContents).joined(separator: "\n"))
    }

    /// Hot host directories in compose volume lines
    public static func hotPaths(inText text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- /") else { continue }
            let volume = trimmed.dropFirst(2)
            guard let colon = volume.firstIndex(of: ":"),
                  volume[volume.index(after: colon)...].hasPrefix("/") else { continue }
            let source = String(volume[..<colon])
            let last = source.split(separator: "/").last.map(String.init) ?? ""
            guard hotNames.contains(last), seen.insert(source).inserted else { continue }
            result.append(source)
        }
        return result
    }

    /// Where fast data lives on the server
    public var root: String {
        switch target {
        case .device: return Self.mountPoint
        case .folder(let mount): return mount + "/gryonixnexus-fast"
        }
    }

    public func script() -> String {
        var lines = [
            "#!/bin/bash",
            "set -euo pipefail",
            "FAST=\(ShellQuoting.singleQuoted(root))",
        ]
        switch target {
        case .device(let path): lines += Self.formatLines(path)
        case .folder: lines.append("install -d \"$FAST\"")
        }
        lines += dockerLines() + bindFunction()
        lines += hotPaths.map { "bind_fast \(ShellQuoting.singleQuoted($0))" }
        lines.append("echo \(Self.doneMarker)")
        return lines.joined(separator: "\n") + "\n"
    }

    static func formatLines(_ path: String) -> [String] {
        [
            "DISK=\(ShellQuoting.singleQuoted(path))",
            "if ! mountpoint -q \"$FAST\"; then",
            "  if [ -z \"$(lsblk -nro FSTYPE \"$DISK\" | tr -d '[:space:]')\" ] && [ \"$(lsblk -nro NAME \"$DISK\" | wc -l)\" -eq 1 ]; then",
            "    mkfs.ext4 -q -L gnx-fast \"$DISK\"",
            "  fi",
            "  install -d \"$FAST\"",
            "  uuid=\"$(blkid -s UUID -o value \"$DISK\")\"",
            "  grep -q \"UUID=$uuid $FAST \" /etc/fstab || echo \"UUID=$uuid $FAST ext4 defaults,noatime,nofail 0 2\" >> /etc/fstab",
            "  mount \"$FAST\"",
            "fi",
        ]
    }

    private func dockerLines() -> [String] {
        [
            "if ! command -v docker >/dev/null 2>&1 && [ ! -s /etc/docker/daemon.json ]; then",
            "  install -d /etc/docker \"$FAST/docker\"",
            "  printf '{\\n  \"data-root\": \"%s/docker\"\\n}\\n' \"$FAST\" > /etc/docker/daemon.json",
            "fi",
        ]
    }

    static func bindLine(source: String, target: String) -> String {
        "grep -qF \" \(target) none bind\" /etc/fstab || echo \"\(source) \(target) none bind,nofail,x-systemd.requires-mounts-for=$FAST 0 0\" >> /etc/fstab"
    }

    private func bindFunction() -> [String] {
        [
            "bind_fast() {",
            "  local target=\"$1\" source=\"$FAST/binds$1\"",
            "  install -d \"$source\" \"$target\"",
            "  mountpoint -q \"$target\" && return 0",
            "  if [ -n \"$(ls -A \"$target\")\" ]; then",
            "    echo \"$target already holds data, left in place\"",
            "    return 0",
            "  fi",
            "  grep -qF \" $target none bind\" /etc/fstab || echo \"$source $target none bind,nofail,x-systemd.requires-mounts-for=$FAST 0 0\" >> /etc/fstab",
            "  mount \"$target\"",
            "}",
        ]
    }
}
