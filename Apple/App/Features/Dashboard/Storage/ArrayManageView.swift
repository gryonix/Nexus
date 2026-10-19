import ServerControl
import ServiceCatalog
import SwiftUI

/// One array: its disks and every change it allows now
struct ArrayManageView: View {
    @ObservedObject var model: StorageViewModel
    let array: StorageArray
    @State private var dismiss = DismissHandle()

    private var actions: [ArrayChange.Action] {
        model.hardware.map { ArrayChange.actions(for: array, in: $0) } ?? []
    }

    var body: some View {
        screen.dismissHandle(dismiss)
    }

    @ViewBuilder private var screen: some View {
        Form {
            Section {
                ArrayRow(array: array)
                ForEach(array.members + array.spares, id: \.self) { path in
                    Text(verbatim: StorageChangeText.member(path, in: model.hardware))
                        .font(.caption)
                }
            }
            Section {
                ForEach(actions) { action in
                    NavigationLink(StorageChangeText.title(action)) {
                        ArrayChangeView(model: model, array: array, action: action) { dismiss() }
                    }
                }
            } footer: {
                if actions.isEmpty {
                    Text("Nothing can be changed while the array is not healthy. Repair it first.")
                } else if model.hardware.map(RaidPlan.candidates(in:))?.isEmpty ?? true {
                    Text("Put a new disk into the server to add or replace one.")
                }
            }
        }
        .navigationTitle(Text(verbatim: array.name))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
    }
}

/// One change: what happens, which disks, before and after
struct ArrayChangeView: View {
    @ObservedObject var model: StorageViewModel
    let array: StorageArray
    let action: ArrayChange.Action
    let onDone: () -> Void
    @State private var member: String?
    @State private var first: String?
    @State private var second: String?
    @State private var level: RaidPlan.Level?
    @State private var confirmation = ""

    private var free: [ServerDisk] { model.hardware.map(RaidPlan.candidates(in:)) ?? [] }

    private var change: ArrayChange {
        let picked = [first, second].compactMap { path in free.first { $0.path == path } }
        return ArrayChange(action: action, array: array, member: member,
                           disks: Array(picked.prefix(action.newDisks(for: array))), level: level)
    }

    private var confirmed: Bool {
        let typed = confirmation.trimmingCharacters(in: .whitespaces)
        if action == .delete { return typed == array.name }
        return change.disks.isEmpty || StoragePreparation.confirms(typed)
    }

    private var step: StorageStep? {
        guard let hardware = model.hardware, change.isReady, confirmed else { return nil }
        return .change(change, in: hardware)
    }

    var body: some View {
        Form {
            Section { ArrayRow(array: array) } footer: {
                Text(verbatim: StorageChangeText.explanation(action))
            }
            ArrayChoiceSection(model: model, array: array, action: action, free: free,
                               member: $member, first: $first, second: $second, level: $level)
            if let hardware = model.hardware, change.isReady {
                ArrayPreviewSection(change: change, preview: change.preview(in: hardware), hardware: hardware)
            }
            ArrayConfirmSection(action: action, arrayName: array.name, erases: !change.disks.isEmpty,
                                confirmation: $confirmation)
            StorageSignInSection(model: model)
            StorageRunSection(model: model, title: action == .delete ? "Delete" : "Start", step: step,
                              destructive: action == .delete || !change.disks.isEmpty) { onDone() }
        }
        .navigationTitle(Text(verbatim: StorageChangeText.title(action)))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.loadStoredSecret() }
    }
}

/// The member, new disks and level the change needs
private struct ArrayChoiceSection: View {
    @ObservedObject var model: StorageViewModel
    let array: StorageArray
    let action: ArrayChange.Action
    let free: [ServerDisk]
    @Binding var member: String?
    @Binding var first: String?
    @Binding var second: String?
    @Binding var level: RaidPlan.Level?

    private var disks: Int { action.newDisks(for: array) }

    var body: some View {
        if action.takesMember || disks > 0 || action == .changeLevel {
            Section {
                if action.takesMember {
                    WrappingPicker("Disk", selection: $member) {
                        Text("None").tag(String?.none)
                        ForEach(array.members, id: \.self) { path in
                            Text(verbatim: StorageChangeText.member(path, in: model.hardware)).tag(String?.some(path))
                        }
                    }
                }
                if action == .changeLevel {
                    WrappingPicker("New level", selection: $level) {
                        Text("None").tag(RaidPlan.Level?.none)
                        ForEach(ArrayChange.levels(for: array)) { target in
                            Text(RaidChoiceRows.title(target)).tag(RaidPlan.Level?.some(target))
                        }
                    }
                }
                if disks > 0 { freePicker("New disk", selection: $first, excluding: second) }
                if disks > 1 { freePicker("Second new disk", selection: $second, excluding: first) }
            }
        }
    }

    private func freePicker(_ title: LocalizedStringKey, selection: Binding<String?>, excluding: String?) -> some View {
        WrappingPicker(title, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(free.filter { $0.path != excluding }) { disk in
                Text(verbatim: StorageText.choice(disk)).tag(String?.some(disk.path))
            }
        }
    }
}

/// Space and protection before and after, and what to expect
private struct ArrayPreviewSection: View {
    let change: ArrayChange
    let preview: ArrayChange.Preview
    let hardware: ServerHardware

    var body: some View {
        Section {
            if preview.usableBefore > 0 && change.action != .delete {
                LabeledContent("Space") {
                    Text(verbatim: StorageText.bytes(preview.usableBefore) + " → " + StorageText.bytes(preview.usableAfter))
                }
                LabeledContent("Disks that may fail") {
                    Text(verbatim: "\(preview.failuresBefore) → \(preview.failuresAfter)")
                }
            }
            warnings
        } header: {
            Text("What changes")
        }
    }

    @ViewBuilder private var warnings: some View {
        if preview.takesLong {
            Label("Takes hours on big disks. The server keeps working, and you can close the app.", systemImage: "clock")
        }
        if preview.goesOffline {
            Label("The array's folder goes offline for a few minutes while its filesystem shrinks. Services that keep data there are stopped and started again.",
                  systemImage: "pause.circle")
                .foregroundStyle(.orange)
        }
        if preview.failuresBefore > 0 && preview.failuresAfter == 0 && change.action != .delete {
            Label("After this, one failed disk loses everything on the array.", systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        }
        if [.remove, .changeLevel, .delete].contains(change.action) {
            Label("Make a backup first.", systemImage: "externaldrive.badge.timemachine")
        }
        if change.action == .detach || change.action == .replace, let member = change.member {
            Label(UIL10n.string("Pull out afterwards: %@", StorageChangeText.member(member, in: hardware)),
                  systemImage: "hand.point.right")
        }
    }
}

/// Typed confirmation: ERASE, or the array's name
private struct ArrayConfirmSection: View {
    let action: ArrayChange.Action
    let arrayName: String
    let erases: Bool
    @Binding var confirmation: String

    var body: some View {
        if action == .delete {
            Section {
                TextField(text: $confirmation) { Text(verbatim: arrayName) }.autocorrectionDisabled()
            } footer: {
                Text(verbatim: UIL10n.string("Everything on the array's disks is erased. Type %@ to confirm.", arrayName))
            }
        } else if erases {
            Section {
                TextField(UIL10n.string("ERASE"), text: $confirmation).autocorrectionDisabled()
            } footer: {
                Text("Everything on the new disk is erased. Type \(UIL10n.string("ERASE")) to confirm.")
            }
        }
    }
}
