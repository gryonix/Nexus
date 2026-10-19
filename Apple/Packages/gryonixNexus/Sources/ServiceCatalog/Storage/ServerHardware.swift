import Foundation

/// One whole disk the server reports
public struct ServerDisk: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case nvme, ssd, hdd }

    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let kind: Kind
    public let model: String
    /// Mount points of the disk and its partitions
    public let mountpoints: [String]
    public let filesystems: [String]
    public let partitionCount: Int
    public internal(set) var raidMember: Bool
    /// Filesystem labels on the disk and its partitions
    public var labels: [String] = []
    /// The array this disk belongs to, as mdadm's UUID
    public var raidUUID: String?
    /// The array's name without its host prefix
    public var raidName: String?
    /// Serial number printed on the disk's label
    public var serial = ""
    /// USB, hot-pluggable or marked removable by the kernel
    public var removable = false

    public var id: String { path }

    /// A cache disk a past install left behind
    public var isEarlierCache: Bool {
        labels.contains(FastStoragePlan.label) && dataMount == nil && !isSystem
    }

    public var isSystem: Bool {
        mountpoints.contains { Self.systemMounts.contains($0) }
    }

    public var isBlank: Bool { partitionCount == 0 && filesystems.isEmpty && !raidMember }

    public var isFast: Bool { kind != .hdd }

    /// A mounted data filesystem that is not the system
    public var dataMount: String? {
        isSystem ? nil : mountpoints.first { $0.hasPrefix("/") }
    }

    static let systemMounts: Set<String> = ["/", "/boot", "/boot/efi", "/usr", "/var", "[SWAP]"]

    public init(name: String, path: String, sizeBytes: Int64, kind: Kind, model: String,
                mountpoints: [String], filesystems: [String], partitionCount: Int,
                raidMember: Bool) {
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.model = model
        self.mountpoints = mountpoints
        self.filesystems = filesystems
        self.partitionCount = partitionCount
        self.raidMember = raidMember
    }
}

/// One lsblk row, with the whole disk it sits on
public struct BlockNode: Sendable, Hashable {
    public let name: String
    public let path: String
    public let type: String
    public let fstype: String
    public let label: String
    public let uuid: String
    public let mountpoint: String?
    /// Path of the disk this node lives on
    public let disk: String
}

/// What a server is built from, read before installing
public struct ServerHardware: Sendable, Hashable {
    public let cpuCores: Int
    public let memoryBytes: Int64
    public let architecture: String
    public let rootFreeBytes: Int64
    public private(set) var disks: [ServerDisk]
    /// Assembled md devices seen under their member disks
    public var volumes: [ArrayVolume] = []
    /// The raw /proc/mdstat text
    public var mdstat = ""
    /// Every disk, partition and device above them
    public var blockNodes: [BlockNode] = []
    /// `zpool status -LP`
    public var zpoolStatus = ""
    /// `zfs list -d 0`: pool and mountpoint per line
    public var zfsMounts = ""
    /// Mounted btrfs filesystems: uuid, data profile, devices, missing
    public var btrfsFilesystems = ""
    /// `lvs` for RAID volumes; empty without passwordless sudo
    public var lvmReport = ""
    /// The background disk job, if one ran
    public var diskJob: DiskJob?
    /// Swap space the machine already has
    public var swapBytes: Int64 = 0

    public init(cpuCores: Int, memoryBytes: Int64, architecture: String,
                rootFreeBytes: Int64, disks: [ServerDisk]) {
        self.cpuCores = cpuCores
        self.memoryBytes = memoryBytes
        self.architecture = architecture
        self.rootFreeBytes = rootFreeBytes
        self.disks = disks
    }

    public static let beginMarker = "GRYONIXNEXUS_HW_BEGIN"
    public static let endMarker = "GRYONIXNEXUS_HW_END"

    /// Read-only probe; prints key=value lines between markers
    public static let probeCommand = [
        "echo \(beginMarker)",
        "echo \"cpu=$(nproc 2>/dev/null || echo 0)\"",
        "echo \"mem=$(awk '/^MemTotal:/ {printf \"%.0f\", $2 * 1024}' /proc/meminfo 2>/dev/null)\"",
        "echo \"swap=$(awk '/^SwapTotal:/ {printf \"%.0f\", $2 * 1024}' /proc/meminfo 2>/dev/null)\"",
        "echo \"arch=$(uname -m)\"",
        "echo \"rootfree=$(df -B1 --output=avail / 2>/dev/null | tail -n 1 | tr -d ' ')\"",
        "echo \"lsblk=$(lsblk -J -b -o NAME,PATH,SIZE,ROTA,TYPE,MOUNTPOINT,FSTYPE,LABEL,UUID,MODEL,TRAN,SERIAL,RM,HOTPLUG 2>/dev/null | tr -d '\\n')\"",
        "echo \"mdstat=$(cat /proc/mdstat 2>/dev/null | tr '\\n' '|')\"",
        "echo \"zpool=$(zpool status -LP 2>/dev/null | tr '\\t\\n' ' |')\"",
        "echo \"zfsmount=$(zfs list -H -d 0 -o name,mountpoint 2>/dev/null | tr '\\t\\n' ' |')\"",
        "echo \"btrfs=$(for d in $(ls -d /sys/fs/btrfs/*-* 2>/dev/null); do "
            + "printf '%s %s %s %s|' \"${d##*/}\" "
            + "\"$(ls \"$d/allocation/data\" 2>/dev/null | grep -xE 'dup|raid[0-9c]+' | head -n 1)\" "
            + "\"$(ls \"$d/devinfo\" 2>/dev/null | wc -l | tr -d ' ')\" "
            + "\"$(cat \"$d\"/devinfo/*/missing 2>/dev/null | grep -c 1)\"; done)\"",
        "echo \"lvm=$(sudo -n lvs --noheadings --separator ';' "
            + "-o vg_name,lv_name,segtype,lv_health_status,sync_percent 2>/dev/null | tr -d ' ' | tr '\\n' '|')\"",
        DiskJob.probeLine,
        "echo \(endMarker)",
    ].joined(separator: "; ")

    public static func parse(_ output: String) -> ServerHardware? {
        guard let begin = output.range(of: beginMarker),
              let end = output.range(of: endMarker, range: begin.upperBound..<output.endIndex)
        else { return nil }
        var fields: [String: String] = [:]
        for line in output[begin.upperBound..<end.lowerBound].split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            fields[key] = String(line[line.index(after: equals)...])
        }
        var hardware = ServerHardware(
            cpuCores: Int(fields["cpu"] ?? "") ?? 0,
            memoryBytes: Int64(fields["mem"] ?? "") ?? 0,
            architecture: fields["arch"]?.trimmingCharacters(in: .whitespaces) ?? "",
            rootFreeBytes: Int64(fields["rootfree"] ?? "") ?? 0,
            disks: LsblkReader.disks(fromJSON: fields["lsblk"] ?? ""))
        hardware.volumes = LsblkReader.volumes(fromJSON: fields["lsblk"] ?? "")
        hardware.mdstat = (fields["mdstat"] ?? "").replacingOccurrences(of: "|", with: "\n")
        hardware.blockNodes = LsblkReader.nodes(fromJSON: fields["lsblk"] ?? "")
        hardware.zpoolStatus = (fields["zpool"] ?? "").replacingOccurrences(of: "|", with: "\n")
        hardware.zfsMounts = (fields["zfsmount"] ?? "").replacingOccurrences(of: "|", with: "\n")
        hardware.btrfsFilesystems = (fields["btrfs"] ?? "").replacingOccurrences(of: "|", with: "\n")
        hardware.lvmReport = (fields["lvm"] ?? "").replacingOccurrences(of: "|", with: "\n")
        hardware.diskJob = fields["diskjob"].flatMap(DiskJob.parse)
        hardware.swapBytes = Int64(fields["swap"] ?? "") ?? 0
        let pooled = Set(StorageArray.all(in: hardware).filter { $0.kind != .hardware && !$0.isForeignSystemPool }
            .flatMap { $0.members + $0.failed + $0.spares }.compactMap(hardware.diskPath(containing:)))
        hardware = hardware.markingMembers(pooled)
        return hardware
    }

    /// The whole disk a disk or partition path sits on
    public func diskPath(containing path: String) -> String? {
        if disks.contains(where: { $0.path == path }) { return path }
        return blockNodes.first { $0.path == path }?.disk
    }

    private func markingMembers(_ paths: Set<String>) -> ServerHardware {
        var copy = self
        copy.disks = disks.map { disk in
            var disk = disk
            if paths.contains(disk.path) { disk.raidMember = true }
            return disk
        }
        return copy
    }
}

/// Turns `lsblk -J` output into whole disks
enum LsblkReader {
    static func disks(fromJSON json: String) -> [ServerDisk] {
        devices(json).compactMap(disk(from:))
    }

    /// Every node under every real disk, tagged with that disk
    static func nodes(fromJSON json: String) -> [BlockNode] {
        devices(json).filter { disk(from: $0) != nil }.flatMap { device -> [BlockNode] in
            let diskPath = string(device["path"]).isEmpty ? "/dev/\(string(device["name"]))" : string(device["path"])
            return ([device] + descendants(of: device["children"] as? [[String: Any]] ?? [])).map { node in
                let name = string(node["name"])
                return BlockNode(name: name, path: string(node["path"]).isEmpty ? "/dev/\(name)" : string(node["path"]),
                                 type: string(node["type"]), fstype: string(node["fstype"]),
                                 label: string(node["label"]), uuid: string(node["uuid"]),
                                 mountpoint: optional(node["mountpoint"]), disk: diskPath)
            }
        }
    }

    /// Every md device, once, with its mount and filesystem
    static func volumes(fromJSON json: String) -> [ArrayVolume] {
        var seen = Set<String>()
        return descendants(of: devices(json)).compactMap { node in
            guard string(node["type"]).hasPrefix("raid"), seen.insert(string(node["name"])).inserted
            else { return nil }
            return ArrayVolume(name: string(node["name"]), level: string(node["type"]),
                               mountpoint: optional(node["mountpoint"]),
                               filesystem: optional(node["fstype"]), label: optional(node["label"]))
        }
    }

    private static func devices(_ json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return root["blockdevices"] as? [[String: Any]] ?? []
    }

    private static func optional(_ value: Any?) -> String? {
        let text = string(value)
        return text.isEmpty ? nil : text
    }

    private static func disk(from device: [String: Any]) -> ServerDisk? {
        guard string(device["type"]) == "disk" else { return nil }
        let name = string(device["name"])
        guard !name.hasPrefix("zram"), !name.hasPrefix("loop") else { return nil }
        let children = device["children"] as? [[String: Any]] ?? []
        let nodes = [device] + descendants(of: children)
        let filesystems = nodes.map { string($0["fstype"]) }.filter { !$0.isEmpty }
        let member = nodes.first { string($0["fstype"]) == "linux_raid_member" }
        var disk = ServerDisk(
            name: name,
            path: string(device["path"]).isEmpty ? "/dev/\(name)" : string(device["path"]),
            sizeBytes: int64(device["size"]),
            kind: kind(of: device),
            model: string(device["model"]).trimmingCharacters(in: .whitespaces),
            mountpoints: nodes.map { string($0["mountpoint"]) }.filter { !$0.isEmpty },
            filesystems: filesystems,
            partitionCount: children.filter { string($0["type"]) == "part" }.count,
            raidMember: filesystems.contains("linux_raid_member")
                || nodes.contains { string($0["type"]).hasPrefix("raid") })
        disk.serial = string(device["serial"]).trimmingCharacters(in: .whitespaces)
        disk.removable = flag(device["rm"]) || flag(device["hotplug"]) || string(device["tran"]) == "usb"
        disk.labels = nodes.filter { !string($0["type"]).hasPrefix("raid") }
            .map { string($0["label"]) }.filter { !$0.isEmpty }
        if let member {
            disk.raidUUID = mdadmUUID(string(member["uuid"]))
            disk.raidName = string(member["label"]).split(separator: ":").last.map(String.init)
        }
        return disk
    }

    /// lsblk's dashed UUID in mdadm's colon form
    static func mdadmUUID(_ dashed: String) -> String? {
        let hex = dashed.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32 else { return nil }
        return stride(from: 0, to: 32, by: 8).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 8)])
        }.joined(separator: ":")
    }

    private static func descendants(of nodes: [[String: Any]]) -> [[String: Any]] {
        nodes.flatMap { [$0] + descendants(of: $0["children"] as? [[String: Any]] ?? []) }
    }

    private static func kind(of device: [String: Any]) -> ServerDisk.Kind {
        if string(device["tran"]) == "nvme" || string(device["name"]).hasPrefix("nvme") { return .nvme }
        return flag(device["rota"]) ? .hdd : .ssd
    }

    private static func string(_ value: Any?) -> String {
        (value as? String) ?? ""
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        return Int64(string(value)) ?? 0
    }

    private static func flag(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        return string(value) == "1" || string(value) == "true"
    }
}
