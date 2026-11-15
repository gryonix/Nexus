import ServerControl
import SwiftUI

/// Add, remove and reorder the keys above the keyboard.
struct TerminalAccessoryEditor: View {
    @ObservedObject private var model = TerminalAccessoryModel.shared

    var body: some View {
        List {
            Section {
                ForEach(model.layout.keys) { key in
                    Text(verbatim: key.label)
                }
                .onDelete { offsets in
                    model.update { layout in offsets.sorted(by: >).forEach { layout.remove(at: $0) } }
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    model.update { $0.move(from: from, to: destination > from ? destination - 1 : destination) }
                }
            } footer: {
                Text("Drag to reorder, swipe to remove.")
            }
            Section("Add a key") {
                ForEach(TerminalAccessoryKey.Group.allCases, id: \.self) { group in
                    groupMenu(group)
                }
            }
            Section {
                Button("Reset to default") { model.update { $0.reset() } }
            }
        }
        .screenTitle("Keyboard keys")
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
    }

    private func groupMenu(_ group: TerminalAccessoryKey.Group) -> some View {
        let available = TerminalAccessoryCatalog.all.filter {
            $0.group == group && !model.layout.ids.contains($0.id)
        }
        return Menu {
            ForEach(available) { key in
                Button(key.label) { model.update { $0.add(key.id) } }
            }
        } label: {
            Text(title(of: group))
        }
        .disabled(available.isEmpty)
    }

    private func title(of group: TerminalAccessoryKey.Group) -> LocalizedStringKey {
        switch group {
        case .special: return "Special keys"
        case .symbols: return "Symbols"
        case .function: return "Function keys"
        case .control: return "Control keys"
        }
    }
}
