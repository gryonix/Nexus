import SwiftUI

extension View {
    /// Tinted label, white while focused on the TV
    func focusLegibleForeground(_ tint: Color) -> some View {
        modifier(FocusLegibleForeground(tint: tint))
    }
}

private struct FocusLegibleForeground: ViewModifier {
    let tint: Color
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #endif

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.foregroundStyle(isFocused ? Color.white : tint)
        #else
        content.foregroundStyle(tint)
        #endif
    }
}
