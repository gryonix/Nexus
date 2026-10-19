import SwiftUI

struct InfoNote<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More about this"))
        .sheet(isPresented: $showing) {
            InfoNoteSheet(title: title, content: content)
        }
    }
}

extension InfoNote where Content == Text {
    /// The common case: one sentence or paragraph
    init(_ title: LocalizedStringKey, _ message: LocalizedStringKey) {
        self.title = title
        self.content = { Text(message) }
    }
}

extension View {
    /// Trailing "i" on a single row — `Label("…", …).infoNote("Title", "…")`
    func infoNote(_ title: LocalizedStringKey, _ message: LocalizedStringKey) -> some View {
        HStack {
            self
            Spacer(minLength: 8)
            InfoNote(title, message)
        }
    }

    /// Trailing "i" with composed, multi-part content
    func infoNote<Content: View>(_ title: LocalizedStringKey,
                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        HStack {
            self
            Spacer(minLength: 8)
            InfoNote(title: title, content: content)
        }
    }
}

struct InfoSectionHeader<Content: View>: View {
    let title: LocalizedStringKey
    /// Shown as a small circular arrow left of the "i"
    var refresh: (() async -> Void)?
    var isRefreshing = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            if let refresh {
                RefreshButton(label: "Read this again", isBusy: isRefreshing, action: refresh)
            }
            InfoNote(title: title, content: content)
        }
    }
}

extension InfoSectionHeader where Content == Text {
    init(_ title: LocalizedStringKey, note: LocalizedStringKey) {
        self.title = title
        self.content = { Text(note) }
    }
}

extension InfoSectionHeader {
    /// Composed note — `InfoSectionHeader("Agent") { Text(…); if x { Text(…) } }`
    init(_ title: LocalizedStringKey, @ViewBuilder note: @escaping () -> Content) {
        self.title = title
        self.content = note
    }

    /// Composed note with a button that re-reads the section
    init(_ title: LocalizedStringKey, isRefreshing: Bool,
         refresh: @escaping () async -> Void,
         @ViewBuilder note: @escaping () -> Content) {
        self.title = title
        self.refresh = refresh
        self.isRefreshing = isRefreshing
        self.content = note
    }
}

private struct InfoNoteSheet<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle(Text(title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .phoneSheetDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
