import ServerControl
import SwiftUI
import UniformTypeIdentifiers

/// Settings for how terminals look.
struct TerminalDesignView: View {
    var serverID: UUID?

    @ObservedObject private var store = TerminalAppearanceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TerminalTheme?
    @State private var importing = false
    @State private var importError: String?

    private var look: TerminalAppearance { store.appearance }

    var body: some View {
        Form {
            themeSection
            if serverID != nil { serverSection }
            fontSection
            cursorSection
            backgroundSection
            customSection
            #if os(iOS)
            Section {
                NavigationLink { TerminalAccessoryEditor() } label: { Text("Keyboard keys") }
            }
            #endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .screenTitle("Terminal design")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $editing) { theme in
            NavigationStack {
                TerminalThemeEditor(theme: theme) { saved in store.update { $0.save(saved) } }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .xml, .propertyList]) { result in
            importFile(result)
        }
        .alert("The file is not an iTerm2 colour scheme.", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func themePicker(_ title: LocalizedStringKey, id: WritableKeyPath<TerminalAppearance, String>) -> some View {
        Picker(title, selection: Binding(get: { look[keyPath: id] },
                                         set: { value in store.update { $0[keyPath: id] = value } })) {
            ForEach(look.allThemes) { Text(verbatim: $0.name).tag($0.id) }
        }
    }

    private var themeSection: some View {
        Section {
            Toggle("Follow system appearance", isOn: Binding(
                get: { look.followSystem }, set: { value in store.update { $0.followSystem = value } }))
            if look.followSystem {
                themePicker("Dark theme", id: \.darkThemeID)
                themePicker("Light theme", id: \.lightThemeID)
            } else {
                themePicker("Theme", id: \.fixedThemeID)
            }
        }
    }

    private var serverSection: some View {
        Section {
            Picker("Theme for this server", selection: Binding(
                get: { serverID.flatMap { look.serverThemes[$0.uuidString] } ?? "" },
                set: { value in setServerTheme(value) })) {
                Text("Same as default").tag("")
                ForEach(look.allThemes) { Text(verbatim: $0.name).tag($0.id) }
            }
        }
    }

    private func setServerTheme(_ id: String) {
        guard let key = serverID?.uuidString else { return }
        store.update { $0.serverThemes[key] = id.isEmpty ? nil : id }
    }

    private var fontSection: some View {
        Section("Font") {
            Picker("Font", selection: Binding(
                get: { look.fontName ?? "" }, set: { value in store.update { $0.fontName = value.isEmpty ? nil : value } })) {
                ForEach(TerminalFonts.choices, id: \.self) { Text(verbatim: TerminalFonts.title($0)).tag($0 ?? "") }
            }
            VStack(alignment: .leading) {
                Text("Font size: \(Int(look.fontSize))")
                Slider(value: Binding(get: { look.fontSize }, set: { value in store.update { $0.fontSize = value.rounded() } }),
                       in: TerminalAppearance.fontSizeRange)
            }
        }
    }

    private var cursorSection: some View {
        Section("Cursor") {
            Picker("Cursor shape", selection: Binding(
                get: { look.cursorShape }, set: { value in store.update { $0.cursorShape = value } })) {
                Text("Block cursor").tag(TerminalCursorShape.block)
                Text("Bar").tag(TerminalCursorShape.bar)
                Text("Underline").tag(TerminalCursorShape.underline)
            }
            Toggle("Blinking cursor", isOn: Binding(
                get: { look.cursorBlink }, set: { value in store.update { $0.cursorBlink = value } }))
        }
    }

    private var backgroundSection: some View {
        Section("Background") {
            VStack(alignment: .leading) {
                Text("Opacity: \(Int(look.opacity * 100))%")
                Slider(value: Binding(get: { look.opacity }, set: { value in store.update { $0.opacity = value } }),
                       in: TerminalAppearance.opacityRange)
            }
            Toggle("Blur behind the terminal", isOn: Binding(
                get: { look.blur }, set: { value in store.update { $0.blur = value } }))
        }
    }

    private var customSection: some View {
        Section("Custom themes") {
            ForEach(look.customThemes) { theme in
                Button { editing = theme } label: { Text(verbatim: theme.name) }
                    .swipeActions { Button("Delete", role: .destructive) { store.update { $0.removeCustom(theme.id) } }.dangerTint() }
            }
            Button("New theme") { editing = newTheme() }
            Button("Import iTerm2 colours…") { importing = true }
        }
    }

    private func newTheme() -> TerminalTheme {
        var base = look.theme(isDark: true, server: nil)
        base.id = "custom-" + UUID().uuidString.lowercased()
        base.name = UIL10n.string("New theme")
        return base
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let theme = try ITermColorsImport.theme(from: data, name: url.deletingPathExtension().lastPathComponent)
            store.update { $0.save(theme) }
        } catch {
            importError = error.localizedDescription
        }
    }
}
