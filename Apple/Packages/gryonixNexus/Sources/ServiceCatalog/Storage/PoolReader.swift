import Foundation

enum PoolReader {
    // MARK: ZFS

    static func zfs(in hardware: ServerHardware) -> [StorageArray] {
        let mounts = zfsMounts(hardware.zfsMounts)
        let active = ZpoolReader.pools(hardware.zpoolStatus).map { pool in
            var array = StorageArray(kind: .zfs, name: pool.name, uuid: nil, device: nil, level: pool.level,
                                     members: pool.members, failed: pool.failed,
                                     slots: pool.members.count + pool.failed.count, working: pool.members.count,
                                     state: pool.state, mountpoint: mounts[pool.name], filesystem: "zfs")
            array.spares = pool.spares
            array.groups = max(pool.groups, 1)
            return array
        }
        let running = Set(active.map(\.name))
        let leftovers = Dictionary(grouping: hardware.blockNodes.filter {
            $0.fstype == "zfs_member" && !$0.label.isEmpty && !running.contains($0.label)
        }, by: { $0.uuid.isEmpty ? $0.label : $0.uuid })
        let stopped = leftovers.values.compactMap { nodes -> StorageArray? in
            guard let first = nodes.first else { return nil }
            return StorageArray(kind: .zfs, name: first.label, uuid: first.uuid.isEmpty ? nil : first.uuid,
                                device: nil, level: "", members: nodes.map(\.path), failed: [],
                                slots: nodes.count, working: nodes.count, state: .stopped,
                                mountpoint: nil, filesystem: "zfs")
        }
        return active + stopped.sorted { $0.name < $1.name }
    }

    private static func zfsMounts(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[1].hasPrefix("/") else { continue }
            out[parts[0]] = parts[1]
        }
        return out
    }

    // MARK: btrfs

    static func btrfs(in hardware: ServerHardware) -> [StorageArray] {
        let mounted = btrfsMounted(hardware.btrfsFilesystems)
        let groups = Dictionary(grouping: hardware.blockNodes.filter {
            $0.fstype == "btrfs" && !$0.uuid.isEmpty
        }, by: \.uuid)
        return groups.compactMap { uuid, nodes -> StorageArray? in
            let info = mounted[uuid]
            let slots = max(info?.devices ?? 0, nodes.count)
            guard slots >= 2 else { return nil }
            let state: StorageArray.State = info == nil ? .unknown
                : (info?.missing ?? 0) > 0 ? .degraded : .clean
            let label = nodes.first { !$0.label.isEmpty }?.label
            return StorageArray(kind: .btrfs, name: label ?? "btrfs", uuid: uuid, device: nil,
                                level: info?.profile ?? "", members: nodes.map(\.path), failed: [],
                                slots: slots, working: slots - (info?.missing ?? 0), state: state,
                                mountpoint: nodes.compactMap(\.mountpoint).first, filesystem: "btrfs")
        }.sorted { $0.name < $1.name }
    }

    private struct BtrfsInfo {
        let profile: String
        let devices: Int
        let missing: Int
    }

    private static func btrfsMounted(_ text: String) -> [String: BtrfsInfo] {
        var out: [String: BtrfsInfo] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, let devices = Int(parts[2]) else { continue }
            out[parts[0]] = BtrfsInfo(profile: parts[1], devices: devices, missing: Int(parts[3]) ?? 0)
        }
        return out
    }

    // MARK: LVM

    /// RAID logical volumes, seen in lsblk as `vg-lv_rimage_N`
    static func lvm(in hardware: ServerHardware) -> [StorageArray] {
        let images = hardware.blockNodes.filter { $0.type == "lvm" && $0.name.range(of: #"_rimage_\d+$"#, options: .regularExpression) != nil }
        let groups = Dictionary(grouping: images) { node in
            String(node.name[..<node.name.range(of: "_rimage_", options: .backwards)!.lowerBound])
        }
        let report = lvmReport(hardware.lvmReport)
        return groups.map { volume, nodes in
            let row = report[volume]
            let members = Array(Set(nodes.map(\.disk))).sorted()
            var state = StorageArray.State.unknown
            if let row {
                if !row.health.isEmpty { state = .degraded }
                else if let sync = row.sync, sync < 100 { state = .rebuilding(percent: sync) }
                else { state = .clean }
            }
            let top = hardware.blockNodes.first { $0.name == volume }
            return StorageArray(kind: .lvm, name: volume, uuid: nil, device: "/dev/mapper/\(volume)",
                                level: row?.segtype ?? "", members: members, failed: [],
                                slots: nodes.count, working: nodes.count, state: state,
                                mountpoint: top?.mountpoint, filesystem: top.map(\.fstype).flatMap { $0.isEmpty ? nil : $0 })
        }.sorted { $0.name < $1.name }
    }

    private struct LvmRow {
        let segtype: String
        let health: String
        let sync: Double?
    }

    private static func lvmReport(_ text: String) -> [String: LvmRow] {
        var out: [String: LvmRow] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5, parts[2].hasPrefix("raid") else { continue }
            out[mapperName(vg: parts[0], lv: parts[1])] = LvmRow(segtype: parts[2], health: parts[3],
                                                                 sync: Double(parts[4]))
        }
        return out
    }

    /// Device-mapper doubles every dash inside a name
    static func mapperName(vg: String, lv: String) -> String {
        vg.replacingOccurrences(of: "-", with: "--") + "-" + lv.replacingOccurrences(of: "-", with: "--")
    }

    // MARK: RAID controllers

    static let controllerModels = ["PERC", "MEGARAID", "LOGICAL VOLUME", "SERVERAID",
                                   "SMART ARRAY", "ADAPTEC", "ASR8", "MR9", "RAID"]

    static func controllers(in hardware: ServerHardware) -> [StorageArray] {
        hardware.disks.filter { disk in
            let model = disk.model.uppercased()
            return controllerModels.contains { model.contains($0) }
        }.map { disk in
            StorageArray(kind: .hardware, name: disk.model, uuid: disk.path, device: disk.path,
                         level: "", members: [disk.path], failed: [], slots: 1, working: 1,
                         state: .unknown, mountpoint: disk.dataMount, filesystem: disk.filesystems.first)
        }
    }
}

/// Reads `zpool status -LP` with tabs turned into spaces
enum ZpoolReader {
    struct Pool {
        var name: String
        var state = StorageArray.State.clean
        var level = ""
        var members: [String] = []
        var failed: [String] = []
        var spares: [String] = []
        /// Top-level mirror or raidz groups
        var groups = 0
    }

    static let groupSections: Set<String> = ["logs", "cache", "spares", "special", "dedup"]

    static func pools(_ text: String) -> [Pool] {
        var pools: [Pool] = []
        var inConfig = false
        var section = ""
        var progress = Activity.idle
        for raw in text.split(separator: "\n").map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("pool:") {
                pools.append(Pool(name: value(line)))
                inConfig = false
                section = ""
                progress = .idle
                continue
            }
            guard !pools.isEmpty else { continue }
            let index = pools.count - 1
            if line.hasPrefix("state:") {
                pools[index].state = value(line) == "ONLINE" ? .clean : .degraded
            } else if let started = activity(line) {
                progress = started
            } else if progress != .idle, let match = line.range(of: #"[0-9.]+% done"#, options: .regularExpression) {
                let percent = Double(line[match].split(separator: "%")[0]) ?? 0
                if progress == .rebuild { pools[index].state = .rebuilding(percent: percent) }
                else if pools[index].state == .clean { pools[index].state = .checking(percent: percent) }
                progress = .idle
            } else if line.hasPrefix("config:") {
                inConfig = true
            } else if line.hasPrefix("errors:") {
                inConfig = false
            } else if inConfig {
                device(line, section: &section, into: &pools[index])
            }
        }
        return pools
    }

    /// Work that a later `% done` line measures
    enum Activity { case idle, rebuild, check }

    /// nil when the line starts no scan, expansion or removal
    private static func activity(_ line: String) -> Activity? {
        guard ["scan:", "expand:", "remove:"].contains(where: line.hasPrefix) else { return nil }
        guard line.contains("in progress") else { return .idle }
        return line.hasPrefix("scan:") && line.contains("scrub") ? .check : .rebuild
    }

    private static func value(_ line: String) -> String {
        line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private static func device(_ line: String, section: inout String, into pool: inout Pool) {
        let words = line.split(separator: " ").map(String.init)
        guard let name = words.first, name != "NAME", name != pool.name else { return }
        if groupSections.contains(name) { section = name; return }
        if let group = name.range(of: #"^(mirror|raidz[123]?|draid[123]?)"#, options: .regularExpression) {
            if section.isEmpty { pool.groups += 1 }
            if pool.level.isEmpty {
                let kind = String(name[group])
                pool.level = kind == "raidz" ? "raidz1" : kind
            }
            return
        }
        guard words.count >= 2, name.hasPrefix("/") || name.allSatisfy(\.isNumber) else { return }
        if section == "spares" {
            if words[1] == "AVAIL" { pool.spares.append(name) }
            return
        }
        if words[1] == "ONLINE" { pool.members.append(name) } else { pool.failed.append(name) }
        if pool.level.isEmpty, section.isEmpty { pool.level = "stripe" }
        if pool.level == "stripe", section.isEmpty { pool.groups += 1 }
    }
}
