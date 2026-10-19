import SwiftUI

extension ToolbarItemPlacement {
    /// Leading "back" slot that actually leads on both platforms
    static var wizardBack: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .cancellationAction
        #endif
    }
}
