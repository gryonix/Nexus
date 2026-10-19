import SwiftUI

struct RefreshAction {
    let run: @MainActor @Sendable () async -> Void
}

private struct RefreshActionKey: FocusedValueKey {
    typealias Value = RefreshAction
}

extension FocusedValues {
    var refreshAction: RefreshAction? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func refreshableWithShortcut(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        #if os(macOS)
        refreshable(action: action)
            .focusedSceneValue(\.refreshAction, RefreshAction(run: action))
        #else
        refreshable(action: action)
        #endif
    }
}
