import ServerControl
import ServiceCatalog
import SwiftUI

/// One disk's facts, and formatting, disconnecting or finding it
struct DiskManageView: View {
    enum Work: Hashable { case format, release, blink }

    @ObservedObject var model: StorageViewModel
    let disk: ServerDisk
    @Environment(\.dismiss) private var dismiss
    @State private var task = Work.blink
    @State private var filesystem = DiskFormatPlan.Filesystem.ext4
    @State private var confirmation = ""

    private var isFree: Bool {
        model.hardware.map { DiskFormatPlan.candidates(in: $0).contains(disk) } ?? false
    }

    private var releaseMount: String? { DiskReleasePlan.mount(of: disk) }

    private var tasks: [Work] {
        (isFree ? [.format] : []) + (releaseMount == nil ? [] : [.release]) + [.blink]
    }

    private var step: StorageStep? {
        switch task {
        case .format:
            guard let hardware = model.hardware, isFree, StoragePreparation.confirms(confirmation) else { return nil }
            return .format(DiskFormatPlan.plan(for: disk, filesystem: filesystem, in: hardware))
        case .release:
            return releaseMount.map { .release(DiskReleasePlan(mountPoint: $0)) }
        case .blink:
            return .blink(disk)
        }
    }

    var body: some View {
        Form {
            DiskFactsSection(disk: disk)
            Section {
                WrappingPicker("What to do", selection: $task) {
                    ForEach(tasks, id: \.self) { Text(Self.title($0)).tag($0) }
                }
                if task == .format { formatRows }
            } footer: {
                Text(footer)
            }
            StorageSignInSection(model: model)
            StorageRunSection(model: model, title: Self.title(task), step: step,
                              destructive: task == .format) { dismiss() }
        }
        .navigationTitle(Text(verbatim: disk.name))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .task { await model.loadStoredSecret() }
    }

    @ViewBuilder private var formatRows: some View {
        WrappingPicker("Filesystem", selection: $filesystem) {
            Text("ext4 — the standard").tag(DiskFormatPlan.Filesystem.ext4)
            Text("XFS — large files").tag(DiskFormatPlan.Filesystem.xfs)
            Text("Btrfs — snapshots").tag(DiskFormatPlan.Filesystem.btrfs)
        }
        if let hardware = model.hardware {
            LabeledContent("Mounted at") {
                Text(verbatim: DiskFormatPlan.plan(for: disk, filesystem: filesystem, in: hardware).mountPoint)
            }
        }
        TextField(UIL10n.string("ERASE"), text: $confirmation).autocorrectionDisabled()
    }

    private var footer: LocalizedStringKey {
        switch task {
        case .format: return "Everything on the disk is erased. Type \(UIL10n.string("ERASE")) to confirm."
        case .release: return "The disk is unmounted and no longer mounted at start. The data on it stays."
        case .blink: return "The disk is read for half a minute, so its light flickers. Look for it in the case."
        }
    }

    static func title(_ task: Work) -> LocalizedStringKey {
        switch task {
        case .format: return "Format"
        case .release: return "Disconnect"
        case .blink: return "Blink its light"
        }
    }
}

/// Model, serial, size and what the disk does now
private struct DiskFactsSection: View {
    let disk: ServerDisk

    var body: some View {
        Section {
            LabeledContent("Model") { Text(verbatim: disk.model.isEmpty ? "—" : disk.model) }
            LabeledContent("Serial number") { Text(verbatim: disk.serial.isEmpty ? "—" : disk.serial).textSelection(.enabled) }
            LabeledContent("Size") { Text(verbatim: StorageText.kind(disk) + " · " + StorageText.bytes(disk.sizeBytes)) }
            LabeledContent("Used as") { Text(verbatim: StorageText.state(disk)) }
            LabeledContent("Path") { Text(verbatim: disk.path) }
        }
    }
}
