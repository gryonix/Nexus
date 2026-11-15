import SwiftUI

extension View {
    func raisedNavigationTitle() -> some View {
        #if os(iOS) || os(tvOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
