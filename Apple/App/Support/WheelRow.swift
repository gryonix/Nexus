import SwiftUI

/// A value chosen on a wheel under its row
struct WheelRow<Choice: Hashable>: View {
    let title: LocalizedStringKey
    var info: LocalizedStringKey?
    let choices: [Choice]
    @Binding var selection: Choice
    var startsOpen = false
    var disabled = false
    /// The words of the chosen value in the row
    let text: (Choice) -> Text
    /// The words of one wheel line, when they differ
    var line: ((Choice) -> Text)?
    @State private var open: Bool?

    private var isOpen: Bool { (open ?? (startsOpen || Self.demoOpen)) && !disabled }

    private static var demoOpen: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_WHEEL"] != nil
        #else
        false
        #endif
    }

    var body: some View {
        #if os(iOS)
        header
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { open = !isOpen } }
            .listRowSeparator(isOpen ? .hidden : .automatic, edges: .bottom)
            .accessibilityAddTraits(.isButton)
        if isOpen { wheel }
        #else
        stepper
        #endif
    }

    private var header: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            text(selection)
                .foregroundStyle(isOpen ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.trailing)
            if let info { InfoNote(title, info) }
        }
    }

    #if os(iOS)
    private var wheel: some View {
        Picker(title, selection: $selection) {
            ForEach(choices, id: \.self) { choice in
                (line ?? text)(choice).tag(choice)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 132)
    }
    #else
    private var stepper: some View {
        Stepper {
            header
        } onIncrement: {
            move(by: 1)
        } onDecrement: {
            move(by: -1)
        }
        .disabled(disabled)
    }

    private func move(by offset: Int) {
        guard let at = choices.firstIndex(of: selection), choices.indices.contains(at + offset) else { return }
        selection = choices[at + offset]
    }
    #endif
}
