import Foundation
import ServerControl

/// The key row layout, saved on this device.
@MainActor
final class TerminalAccessoryModel: ObservableObject {
    static let shared = TerminalAccessoryModel()

    @Published private(set) var layout: TerminalAccessoryLayout

    private let store: TerminalAccessoryStore

    init(store: TerminalAccessoryStore = TerminalAccessoryStore()) {
        self.store = store
        layout = store.load()
    }

    func update(_ change: (inout TerminalAccessoryLayout) -> Void) {
        var next = layout
        change(&next)
        layout = next
        store.save(next)
    }
}
