import SwiftUI

/// A form picker row with one layout rule
struct WrappingPicker<Selection: Hashable, Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Selection
    @ViewBuilder private let content: Content
    init(_ title: LocalizedStringKey,
         selection: Binding<Selection>,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        Picker(title, selection: $selection) { content }
        #else
        AdaptiveRow(title) { _ in picker }
        #endif
    }

    private var picker: some View {
        Picker(title, selection: $selection) { content }
            .labelsHidden()
            .accessibilityLabel(Text(title))
    }
}

/// Label and value on one line, else stacked
struct AdaptiveRow<Value: View>: View {
    private let title: Text
    private let value: (_ stacked: Bool) -> Value
    @Environment(\.dynamicTypeSize) private var textSize

    init(_ title: LocalizedStringKey, @ViewBuilder value: @escaping (_ stacked: Bool) -> Value) {
        self.title = Text(title)
        self.value = value
    }

    var body: some View {
        if textSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    title.lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    value(false).fixedSize()
                }
                stacked
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            value(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
