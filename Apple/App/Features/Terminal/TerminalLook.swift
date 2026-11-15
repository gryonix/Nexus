import ServerControl
import SwiftTerm
import SwiftUI

#if os(iOS)
typealias LookColor = UIColor
typealias LookFont = UIFont
#else
typealias LookColor = NSColor
typealias LookFont = NSFont
#endif

/// Fonts a terminal can use.
enum TerminalFonts {
    static let choices: [String?] = [nil, "Menlo", "Courier New"]

    static func title(_ name: String?) -> String {
        name ?? UIL10n.string("System monospaced")
    }

    static func font(_ name: String?, size: Double) -> LookFont {
        let points = CGFloat(size)
        if let name, let named = LookFont(name: name, size: points) { return named }
        return LookFont.monospacedSystemFont(ofSize: points, weight: .regular)
    }
}

extension TerminalTheme {
    func color(_ hex: String, alpha: CGFloat = 1) -> LookColor {
        let (red, green, blue) = Self.rgb(hex) ?? (0, 0, 0)
        return LookColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                         blue: CGFloat(blue) / 255, alpha: alpha)
    }

    var terminalColors: [SwiftTerm.Color] {
        ansi.map { hex in
            let (red, green, blue) = Self.rgb(hex) ?? (0, 0, 0)
            return SwiftTerm.Color(red8: UInt16(red), green8: UInt16(green), blue8: UInt16(blue))
        }
    }
}

/// Puts a look onto the emulator view.
enum TerminalLook {
    @MainActor
    static func apply(_ look: TerminalAppearance, theme: TerminalTheme, to view: SwiftTerm.TerminalView) {
        view.installColors(theme.terminalColors)
        view.nativeForegroundColor = theme.color(theme.foreground)
        view.nativeBackgroundColor = theme.color(theme.background)
        view.backgroundOpacity = CGFloat(look.opacity)
        view.caretColor = theme.color(theme.cursor)
        view.selectedTextBackgroundColor = theme.color(theme.selection)
        let font = TerminalFonts.font(look.fontName, size: look.fontSize)
        if view.font.pointSize != font.pointSize || view.font.fontName != font.fontName {
            view.font = font
        }
        view.getTerminal().setCursorStyle(cursorStyle(look))
        #if os(iOS)
        view.backgroundColor = .clear
        #endif
    }

    static func cursorStyle(_ look: TerminalAppearance) -> CursorStyle {
        switch (look.cursorShape, look.cursorBlink) {
        case (.block, true): return .blinkBlock
        case (.block, false): return .steadyBlock
        case (.bar, true): return .blinkBar
        case (.bar, false): return .steadyBar
        case (.underline, true): return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        }
    }
}
