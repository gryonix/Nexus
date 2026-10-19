import SwiftUI

struct AdvancedSection<Content: View>: View {
    private let title: LocalizedStringKey
    private let footer: LocalizedStringKey?
    @ViewBuilder private let content: Content

    init(_ title: LocalizedStringKey = "Advanced", footer: LocalizedStringKey? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        AdvancedRow(title, footer: footer) { content }
            .inSection()
    }
}

struct AdvancedRow<Content: View>: View {
    private let title: LocalizedStringKey
    private let footer: LocalizedStringKey?
    @ViewBuilder private let content: Content
    @State private var expanded = false

    init(_ title: LocalizedStringKey = "Advanced", footer: LocalizedStringKey? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded },
            set: { newValue in withAnimation(.smooth) { expanded = newValue } }
        )) {
            content
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(title, systemImage: "slider.horizontal.3")
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_ADVANCED"] != nil {
                expanded = true
            }
        }
        #endif
    }
}

private extension View {
    func inSection() -> some View { Section { self } }
}
