import SwiftUI

/// The iOS inset-grouped "card" look on every content screen
struct CardList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        Form { content }
            .formStyle(.grouped)
            .formRowButtons()
        #else
        List { content }
            .listRowSpacing(0)
            .bottomBarClearance()
        #endif
    }
}

extension View {
    @ViewBuilder
    func formRowButtons() -> some View {
        #if os(macOS)
        formRowButtonStyle()
        #else
        self
        #endif
    }
}
