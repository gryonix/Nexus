import SwiftUI

struct MenuChoice: View {
    let title: LocalizedStringKey
    /// Whether this is the choice currently in force
    let picked: Bool
    let choose: () -> Void

    init(_ title: LocalizedStringKey, picked: Bool, choose: @escaping () -> Void) {
        self.title = title
        self.picked = picked
        self.choose = choose
    }

    /// What the menu item's tick reads and writes
    var selection: Binding<Bool> {
        Binding(get: { picked }, set: { _ in choose() })
    }

    var body: some View {
        Toggle(isOn: selection) { Text(title) }
    }
}

struct VerbatimMenuChoice: View {
    let title: String
    let picked: Bool
    let choose: () -> Void

    init(_ title: String, picked: Bool, choose: @escaping () -> Void) {
        self.title = title
        self.picked = picked
        self.choose = choose
    }

    var body: some View {
        Toggle(isOn: Binding(get: { picked }, set: { _ in choose() })) {
            Text(verbatim: title)
        }
    }
}
