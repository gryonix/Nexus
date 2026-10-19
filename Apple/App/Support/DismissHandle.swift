import SwiftUI

/// Dismiss action held outside the environment, so reading never rebuilds
@MainActor
final class DismissHandle {
    fileprivate var action: DismissAction?

    func callAsFunction() {
        action?()
    }
}

private struct DismissHandleFiller: ViewModifier {
    let handle: DismissHandle
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        handle.action = dismiss
        return content
    }
}

extension View {
    /// Keeps the handle pointing at this place's dismiss action
    func dismissHandle(_ handle: DismissHandle) -> some View {
        modifier(DismissHandleFiller(handle: handle))
    }
}
