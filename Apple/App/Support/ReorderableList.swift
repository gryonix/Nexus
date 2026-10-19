import SwiftUI

struct ReorderableList<Content: View>: View {
    /// What iOS draws
    enum PhoneContainer {
        /// `CardList`, the app's own settings look
        case cards
        case form
    }

    var phone: PhoneContainer = .cards
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        List { content }
        #else
        switch phone {
        case .cards: CardList { content }
        case .form: Form { content }.bottomBarClearance()
        }
        #endif
    }
}
