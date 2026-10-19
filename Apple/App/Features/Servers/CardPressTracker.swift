import Foundation
import ServerControl

@MainActor
final class CardPressTracker {
    private(set) var pressed: UUID?
    private var held: UUID?

    func press(_ id: UUID) {
        pressed = id
        held = nil
    }

    func markHeld(_ id: UUID) { held = id }

    func wasHeld(_ id: UUID) -> Bool {
        guard held == id else { return false }
        held = nil
        return true
    }

    func target(in row: [Deployment], fallback: Deployment) -> Deployment {
        guard let pressed, let match = row.first(where: { $0.id == pressed }) else {
            return fallback
        }
        return match
    }
}

enum ServerCardHold {
    static let menuDelay: Double = 0.5
}
