import SwiftUI

/// A list row whose tap opens a popup menu
struct MenuRow<Items: View>: View {
    let title: LocalizedStringKey
    let value: String
    var valueStyle = AnyShapeStyle(.secondary)
    var monospaced = false
    @ViewBuilder let items: () -> Items

    init(_ title: LocalizedStringKey, value: String,
         valueStyle: AnyShapeStyle = AnyShapeStyle(.secondary),
         monospaced: Bool = false,
         @ViewBuilder items: @escaping () -> Items) {
        self.title = title
        self.value = value
        self.valueStyle = valueStyle
        self.monospaced = monospaced
        self.items = items
    }

    var body: some View {
        Menu {
            items()
        } label: {
            MenuRowLabel(title: title, value: value, valueStyle: valueStyle, monospaced: monospaced)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// Title, current value and the popup chevron
struct MenuRowLabel: View {
    let title: LocalizedStringKey
    let value: String
    var valueStyle = AnyShapeStyle(.secondary)
    var monospaced = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                Text(verbatim: value)
                    .font(monospaced ? .callout.monospaced() : nil)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(valueStyle)
        } label: {
            Text(title)
        }
        .contentShape(Rectangle())
    }
}
