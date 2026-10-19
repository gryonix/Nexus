import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    func phoneSheetDetents(_ detents: Set<PresentationDetent>) -> some View {
        modifier(PhoneSheetDetents(detents: detents))
    }
}

private struct PhoneSheetDetents: ViewModifier {
    let detents: Set<PresentationDetent>

    private var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        if isPad {
            content.presentationDetents([.large])
        } else {
            content.presentationDetents(detents)
        }
    }
}
