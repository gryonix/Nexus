import SwiftUI

extension View {
    @ViewBuilder
    func bottomBarClearance() -> some View {
        #if os(iOS)
        modifier(BottomBarClearance())
        #else
        self
        #endif
    }
}

#if os(iOS)
extension View {
    /// Every scroll view below clears the bar, pushed screens included
    func bottomBarClearanceEverywhere() -> some View {
        modifier(BottomBarClearance())
    }
}

private struct BottomBarClearance: ViewModifier {
    @Environment(\.barClearance) private var clearance

    /// One branch only: a flip would rebuild every screen below
    func body(content: Content) -> some View {
        content.contentMargins(.bottom, clearance > 0 ? clearance : nil, for: .scrollContent)
    }
}
#endif
