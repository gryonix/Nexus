import SwiftUI

extension EnvironmentValues {
    @Entry var sectionReselectTicks: [AppTab: Int] = [:]
}

extension View {
    func popToRootOnReselect(_ tab: AppTab, _ action: @escaping () -> Void) -> some View {
        modifier(PopToRootOnReselect(tab: tab, action: action))
    }
}

private struct PopToRootOnReselect: ViewModifier {
    let tab: AppTab
    let action: () -> Void
    @Environment(\.sectionReselectTicks) private var ticks

    func body(content: Content) -> some View {
        content.onChange(of: ticks[tab, default: 0]) { _, _ in action() }
    }
}
