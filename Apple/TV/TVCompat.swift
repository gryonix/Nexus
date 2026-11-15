// Stand-ins for SwiftUI and UIKit pieces tvOS lacks, so the phone's screens compile.
// Typing is impossible here by design: text fields and editors only show their value.
#if os(tvOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum TVTitleDisplayMode {
    case automatic, inline, large
}

enum TVTextSelection {
    case enabled, disabled
}

extension View {
    @ViewBuilder
    func navigationBarTitleDisplayMode(_ mode: TVTitleDisplayMode) -> some View {
        if mode == .inline { toolbarTitleDisplayMode(.inline) } else { self }
    }
    func textSelection(_ selection: TVTextSelection) -> some View { self }
    func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }
    func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }
    func scrollContentBackground(_ visibility: Visibility) -> some View { self }
    func scrollDismissesKeyboard(_ mode: TVKeyboardDismissMode) -> some View { self }

    func swipeActions<Content: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true,
                                     @ViewBuilder content: () -> Content) -> some View { self }

    func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                      allowsMultipleSelection: Bool = false,
                      onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View { self }

    func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                      onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View { self }
}

enum TVKeyboardShortcut {
    case defaultAction, cancelAction
}

extension View {
    func keyboardShortcut(_ shortcut: TVKeyboardShortcut) -> some View { self }
}

enum TVKeyboardDismissMode {
    case automatic, immediately, interactively, never
}

extension HorizontalAlignment {
    static var listRowSeparatorLeading: HorizontalAlignment { .leading }
    static var listRowSeparatorTrailing: HorizontalAlignment { .trailing }
}

extension ToolbarItemPlacement {
    static var secondaryAction: ToolbarItemPlacement { .automatic }
    static var topBarTrailing: ToolbarItemPlacement { .automatic }
    static var topBarLeading: ToolbarItemPlacement { .automatic }
    static var navigationBarTrailing: ToolbarItemPlacement { .automatic }
    static var navigationBarLeading: ToolbarItemPlacement { .automatic }
    static var bottomBar: ToolbarItemPlacement { .automatic }
}

extension UIColor {
    static var systemGroupedBackground: UIColor { .clear }
    static var secondarySystemGroupedBackground: UIColor { UIColor.white.withAlphaComponent(0.06) }
    static var tertiarySystemGroupedBackground: UIColor { UIColor.white.withAlphaComponent(0.1) }
    static var systemBackground: UIColor { .clear }
    static var secondarySystemBackground: UIColor { UIColor.white.withAlphaComponent(0.06) }
    static var tertiarySystemBackground: UIColor { UIColor.white.withAlphaComponent(0.1) }
    static var systemFill: UIColor { UIColor.white.withAlphaComponent(0.12) }
    static var secondarySystemFill: UIColor { UIColor.white.withAlphaComponent(0.1) }
    static var tertiarySystemFill: UIColor { UIColor.white.withAlphaComponent(0.08) }
    static var quaternarySystemFill: UIColor { UIColor.white.withAlphaComponent(0.06) }
}

/// A value shown with minus and plus buttons
struct Stepper<Label: View>: View {
    private let label: Label
    private let decrement: () -> Void
    private let increment: () -> Void

    init<V: Strideable>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                        @ViewBuilder label: () -> Label,
                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.label = label()
        decrement = { value.wrappedValue = max(bounds.lowerBound, value.wrappedValue.advanced(by: -step)) }
        increment = { value.wrappedValue = min(bounds.upperBound, value.wrappedValue.advanced(by: step)) }
    }

    init<V: Strideable>(value: Binding<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label,
                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.label = label()
        decrement = { value.wrappedValue = value.wrappedValue.advanced(by: -step) }
        increment = { value.wrappedValue = value.wrappedValue.advanced(by: step) }
    }

    var body: some View {
        HStack(spacing: 24) {
            label
            Spacer()
            Button(action: decrement) { Image(systemName: "minus") }
            Button(action: increment) { Image(systemName: "plus") }
        }
    }
}

extension Stepper where Label == Text {
    init<V: Strideable>(_ title: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>,
                        step: V.Stride = 1) {
        self.init(value: value, in: bounds, step: step) { Text(title) }
    }

    init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>,
                                           step: V.Stride = 1) {
        self.init(value: value, in: bounds, step: step) { Text(title) }
    }
}

struct DatePickerComponents: OptionSet {
    let rawValue: Int
    static let hourAndMinute = DatePickerComponents(rawValue: 1)
    static let date = DatePickerComponents(rawValue: 2)
}

/// A time moved in quarter hours, a date in days
struct DatePicker<Label: View>: View {
    private let label: Label
    @Binding private var selection: Date
    private let components: DatePickerComponents

    init(selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
         @ViewBuilder label: () -> Label) {
        self.label = label()
        _selection = selection
        components = displayedComponents
    }

    private var step: TimeInterval { components.contains(.date) ? 86_400 : 900 }

    var body: some View {
        HStack(spacing: 24) {
            label
            Spacer()
            Button { selection.addTimeInterval(-step) } label: { Image(systemName: "minus") }
            Text(selection, style: components.contains(.date) ? .date : .time)
                .monospacedDigit()
            Button { selection.addTimeInterval(step) } label: { Image(systemName: "plus") }
        }
    }
}

extension DatePicker where Label == Text {
    init(_ title: LocalizedStringKey, selection: Binding<Date>,
         displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, displayedComponents: displayedComponents) { Text(title) }
    }

    init<S: StringProtocol>(_ title: S, selection: Binding<Date>,
                            displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, displayedComponents: displayedComponents) { Text(title) }
    }
}

/// Shows the text; nothing on the TV is typed
struct TextEditor: View {
    @Binding var text: String

    init(text: Binding<String>) {
        _text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(.callout.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A header that shows or hides what is under it
struct DisclosureGroup<Label: View, Content: View>: View {
    @State private var ownExpanded = false
    private let external: Binding<Bool>?
    private let label: Label
    private let content: Content

    init(isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        external = isExpanded
        self.label = label()
        self.content = content()
    }

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        external = nil
        self.label = label()
        self.content = content()
    }

    private var expanded: Binding<Bool> { external ?? $ownExpanded }

    var body: some View {
        Button {
            expanded.wrappedValue.toggle()
        } label: {
            HStack {
                label
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
            }
        }
        if expanded.wrappedValue { content }
    }
}

extension DisclosureGroup where Label == Text {
    init(_ title: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(title) }
    }

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }

    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}
#endif
