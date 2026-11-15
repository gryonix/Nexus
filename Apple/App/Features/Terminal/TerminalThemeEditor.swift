import ServerControl
import SwiftUI

/// Edits one custom theme.
struct TerminalThemeEditor: View {
    @State var theme: TerminalTheme
    let onSave: (TerminalTheme) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section { TextField("Name", text: $theme.name) }
            Section {
                picker("Background", \.background)
                picker("Text", \.foreground)
                picker("Cursor", \.cursor)
                picker("Selection", \.selection)
            }
            Section("Normal colours") { ForEach(0..<8, id: \.self, content: ansiPicker) }
            Section("Bright colours") { ForEach(8..<16, id: \.self, content: ansiPicker) }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .screenTitle("Edit theme")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(theme)
                    dismiss()
                }
                .disabled(theme.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func picker(_ title: LocalizedStringKey, _ path: WritableKeyPath<TerminalTheme, String>) -> some View {
        ColorPicker(title, selection: binding(path), supportsOpacity: false)
    }

    private func ansiPicker(_ index: Int) -> some View {
        ColorPicker(String(index), selection: Binding(
            get: { Color(theme.color(theme.ansi[index])) },
            set: { theme.ansi[index] = Self.hex($0) }), supportsOpacity: false)
    }

    private func binding(_ path: WritableKeyPath<TerminalTheme, String>) -> Binding<Color> {
        Binding(get: { Color(theme.color(theme[keyPath: path])) },
                set: { theme[keyPath: path] = Self.hex($0) })
    }

    static func hex(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if os(iOS)
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        NSColor(color).usingColorSpace(.sRGB)?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return TerminalTheme.hex(red: Double(red), green: Double(green), blue: Double(blue))
    }
}
