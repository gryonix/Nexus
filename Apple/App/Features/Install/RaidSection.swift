import ServiceCatalog
import SwiftUI

/// Builds a software RAID from disks the user ticks
struct RaidSection: View {
    @Binding var target: InstallViewModel.Target
    let hardware: ServerHardware

    private var candidates: [ServerDisk] {
        RaidPlan.candidates(in: hardware).filter {
            $0.path != target.storage.fastDisk && $0.path != target.storage.mirrorDisk
        }
    }

    var body: some View {
        if candidates.count >= 2 {
            Section {
                Toggle("Build a RAID array", isOn: $target.storage.buildsRaid)
                if target.storage.buildsRaid {
                    RaidChoiceRows(choice: $target.storage, candidates: candidates, plan: target.raidPlan)
                }
            } header: {
                Text("RAID array")
            } footer: {
                Text("The array is mounted at \(RaidPlan.mountPoint) — use it for photos, files and media.")
            }
        }
    }
}

/// Level, disks, size and the typed confirmation for one array
struct RaidChoiceRows: View {
    @Binding var choice: StorageChoice
    let candidates: [ServerDisk]
    let plan: RaidPlan?

    var body: some View {
        WrappingPicker("Kind", selection: $choice.raidKind) {
            ForEach(RaidPlan.buildableKinds, id: \.self) { kind in
                Text(verbatim: StorageChangeText.kind(kind)).tag(kind)
            }
        }
        .onChange(of: choice.raidKind) { _, kind in
            if !RaidPlan.levels(for: kind).contains(choice.raidLevel) { choice.raidLevel = .raid1 }
        }
        Text(verbatim: StorageChangeText.kindNote(choice.raidKind))
            .font(.caption)
            .foregroundStyle(.secondary)
        WrappingPicker("Level", selection: $choice.raidLevel) {
            ForEach(RaidPlan.levels(for: choice.raidKind)) { level in
                Text(Self.title(level)).tag(level)
            }
        }
        ForEach(candidates) { disk in
            diskToggle(disk)
        }
        summary
        if choice.raidLevel == .raid0 {
            Label("RAID 0 has no protection: if any one disk fails, everything on the array is lost.",
                  systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        }
        if candidates.contains(where: { choice.raidDisks.contains($0.path) && !$0.isBlank }) {
            Label("A ticked disk holds data. It will be erased.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        TextField(UIL10n.string("ERASE"), text: $choice.confirmation)
            .autocorrectionDisabled()
        Text("Everything on the ticked disks is erased. Type \(UIL10n.string("ERASE")) to confirm.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func diskToggle(_ disk: ServerDisk) -> some View {
        Button {
            if choice.raidDisks.contains(disk.path) {
                choice.raidDisks.remove(disk.path)
            } else {
                choice.raidDisks.insert(disk.path)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: StorageText.title(disk))
                    Text(verbatim: StorageText.detail(disk))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: choice.raidDisks.contains(disk.path)
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var summary: some View {
        if let plan, plan.isValid {
            LabeledContent("Usable space") { Text(verbatim: StorageText.bytes(plan.usableBytes)) }
            LabeledContent("Disks that may fail") {
                Text(verbatim: "\(plan.level.survivableFailures(disks: plan.disks.count))")
            }
        } else if choice.raidLevel == .raid10, choice.raidDisks.count.isMultiple(of: 2) == false {
            Text("RAID 10 needs an even number of disks.").foregroundStyle(.secondary)
        } else {
            Text("Pick at least \(choice.raidLevel.minimumDisks) disks.").foregroundStyle(.secondary)
        }
    }

    static func title(_ level: RaidPlan.Level) -> LocalizedStringKey {
        switch level {
        case .raid0: return "RAID 0 — speed, no protection"
        case .raid1: return "RAID 1 — mirror"
        case .raid5: return "RAID 5 — survives one disk"
        case .raid6: return "RAID 6 — survives two disks"
        case .raid10: return "RAID 10 — mirrored stripes"
        }
    }
}
