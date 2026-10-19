import ServiceCatalog
import SwiftUI

/// Server hardware, its fit, and how its disks are used
struct ServerHardwareSections: View {
    @Binding var target: InstallViewModel.Target
    let requirements: ServerRequirements
    /// A relay keeps no data; its disks are hidden
    var isRelay = false

    var body: some View {
        if let hardware = target.hardware {
            FoundHardwareSection(hardware: hardware,
                                 verdict: HardwareVerdict.judge(hardware, against: requirements))
        }
        if let hardware = target.hardware, !isRelay {
            if !target.arrays.isEmpty {
                ExistingArraysSection(target: $target)
            }
            CacheDiskSection(target: $target, hardware: hardware)
            RaidSection(target: $target, hardware: hardware)
            if let mount = target.dataArrayMount {
                DataPlacementSection(dataOnArray: $target.storage.dataOnArray, mount: mount)
            }
        }
    }
}

/// Where the services keep their files, photos and media
struct DataPlacementSection: View {
    @Binding var dataOnArray: Bool
    let mount: String

    var body: some View {
        Section {
            WrappingPicker("Service data", selection: $dataOnArray) {
                Text(verbatim: UIL10n.string("RAID array %@", mount)).tag(true)
                Text("Main disk").tag(false)
            }
        } header: {
            Text("Where should the data go?")
        } footer: {
            Text("This server has a RAID array. Files, photos and other data of the new services can live on it instead of the main disk.")
        }
    }
}

enum StorageText {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func kind(_ disk: ServerDisk) -> String {
        switch disk.kind {
        case .nvme: return "NVMe"
        case .ssd: return "SSD"
        case .hdd: return "HDD"
        }
    }

    static func state(_ disk: ServerDisk) -> String {
        if disk.isSystem { return UIL10n.string("System disk") }
        if disk.raidMember { return UIL10n.string("In a RAID array") }
        if let mount = disk.dataMount { return UIL10n.string("Mounted at %@", mount) }
        if disk.isBlank { return UIL10n.string("Empty") }
        return UIL10n.string("Holds data")
    }

    static func title(_ disk: ServerDisk) -> String {
        [disk.name, disk.model].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func choice(_ disk: ServerDisk) -> String {
        let base = "\(disk.name) · \(bytes(disk.sizeBytes))"
        return disk.isEarlierCache ? base + " · " + UIL10n.string("from an earlier install") : base
    }

    static func detail(_ disk: ServerDisk) -> String {
        "\(kind(disk)) · \(bytes(disk.sizeBytes)) · \(state(disk))"
    }
}

private struct FoundHardwareSection: View {
    let hardware: ServerHardware
    let verdict: HardwareVerdict

    var body: some View {
        Section {
            VerdictRow(verdict: verdict)
            LabeledContent("Processor") { Text("\(hardware.cpuCores) cores") }
            LabeledContent("Memory") { Text(verbatim: StorageText.bytes(hardware.memoryBytes)) }
            LabeledContent("Swap") { Text(verbatim: SwapRow.current(hardware.swapBytes)) }
            LabeledContent("Free on the system disk") {
                Text(verbatim: StorageText.bytes(hardware.rootFreeBytes))
            }
            LabeledContent("Architecture") { Text(verbatim: hardware.architecture) }
            ForEach(hardware.disks) { disk in
                DiskRow(disk: disk)
            }
        } header: {
            Text("Found on the server")
        }
    }
}

private struct DiskRow: View {
    let disk: ServerDisk

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: StorageText.title(disk))
                Text(verbatim: StorageText.detail(disk))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: disk.isFast ? "memorychip" : "internaldrive")
        }
    }
}

private struct VerdictRow: View {
    let verdict: HardwareVerdict

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .foregroundStyle(tint)
                .font(.headline)
            ForEach(verdict.findings.filter { $0.level != .fits }, id: \.resource) { finding in
                Text(verbatim: line(finding))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch verdict.level {
        case .fits: return "Fits these services"
        case .tight: return "Fits, with little room to spare"
        case .doesNotFit: return "Too small for these services"
        }
    }

    private var symbol: String {
        switch verdict.level {
        case .fits: return "checkmark.seal.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .doesNotFit: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch verdict.level {
        case .fits: return .green
        case .tight: return .orange
        case .doesNotFit: return .red
        }
    }

    private func line(_ finding: HardwareVerdict.Finding) -> String {
        let have = finding.swapBytes > 0
            ? UIL10n.string("%@ + swap %@", StorageText.bytes(finding.haveBytes), StorageText.bytes(finding.swapBytes))
            : StorageText.bytes(finding.haveBytes)
        let need = StorageText.bytes(finding.needBytes)
        switch finding.resource {
        case .memory: return UIL10n.string("Memory: %@, needs %@", have, need)
        case .disk: return UIL10n.string("Free disk: %@, needs %@", have, need)
        }
    }
}

private struct CacheDiskSection: View {
    @Binding var target: InstallViewModel.Target
    let hardware: ServerHardware

    private var candidates: [ServerDisk] {
        FastStoragePlan.candidates(in: hardware)
            .filter { !(target.storage.buildsRaid && target.storage.raidDisks.contains($0.path)) }
    }

    private var earlierMirrors: [StorageArray] {
        target.arrays.filter { $0.isCacheMirror && $0.state == .stopped }
    }

    private var mirrorPartners: [ServerDisk] {
        guard let first = target.fastDisk, first.isBlank else { return [] }
        return candidates.filter { $0.isBlank && $0.path != first.path }
    }

    var body: some View {
        Section {
            if candidates.isEmpty && earlierMirrors.isEmpty {
                Text("No fast disk besides the system one.")
                    .foregroundStyle(.secondary)
            } else {
                WrappingPicker("Cache disk", selection: $target.storage.fastDisk) {
                    Text("None").tag(String?.none)
                    ForEach(earlierMirrors) { array in
                        Text("Cache mirror from an earlier install")
                            .tag(String?.some(StorageChoice.arrayPrefix + array.id))
                    }
                    ForEach(candidates) { disk in
                        Text(verbatim: StorageText.choice(disk)).tag(String?.some(disk.path))
                    }
                }
                if !mirrorPartners.isEmpty {
                    WrappingPicker("Mirror onto", selection: $target.storage.mirrorDisk) {
                        Text("None").tag(String?.none)
                        ForEach(mirrorPartners) { disk in
                            Text(verbatim: StorageText.choice(disk)).tag(String?.some(disk.path))
                        }
                    }
                }
                if target.cacheIsSingleDisk {
                    Label("If this one SSD fails, the databases on it are lost and only backups remain. A second SSD as a mirror keeps them.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Cache disk")
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if target.fastDisk?.isEarlierCache == true || target.storage.fastDisk?.hasPrefix(StorageChoice.arrayPrefix) == true {
            Text("Left by an earlier install: it is brought back as it is, with the databases on it — nothing is formatted.")
        } else if let plan = target.fastPlan, case .device = plan.target {
            Text("The disk is empty and will be formatted. Databases, caches and Docker's data go on it; photos, files and media stay where they are.")
        } else if target.fastPlan != nil {
            Text("The disk keeps its files; a folder is made on it. Databases, caches and Docker's data go there; photos, files and media stay where they are.")
        } else {
            Text("An SSD or NVMe here speeds up databases and caches. Nothing on a disk with files is erased.")
        }
    }
}

/// Arrays found on the disks, brought back, never wiped
private struct ExistingArraysSection: View {
    @Binding var target: InstallViewModel.Target

    var body: some View {
        Section {
            ForEach(target.arrays) { array in
                if array.state == .stopped && array.repairsHere {
                    Toggle(isOn: importBinding(array)) { ArrayRow(array: array) }
                } else {
                    ArrayRow(array: array)
                }
            }
        } header: {
            Text("RAID arrays on this server")
        } footer: {
            Text("Arrays found on the disks are brought back as they are — assembled and mounted, never formatted. Their disks are not offered for a new array.")
        }
    }

    private func importBinding(_ array: StorageArray) -> Binding<Bool> {
        Binding(get: { target.storage.importArrays.contains(array.id) },
                set: { on in
                    if on { target.storage.importArrays.insert(array.id) }
                    else { target.storage.importArrays.remove(array.id) }
                })
    }
}
