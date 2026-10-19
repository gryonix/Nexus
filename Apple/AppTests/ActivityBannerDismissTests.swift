import XCTest

@testable import gryonixNexus

@MainActor
final class ActivityBannerDismissTests: XCTestCase {
    private let registry = RunningOperationsRegistry.shared

    override func setUp() async throws {
        registry.presented = nil
        for entry in registry.entries {
            entry.state.isFinished = true
            registry.dismiss(entry.id)
        }
    }

    private func start(title: String) -> LongOperationState {
        let state = LongOperationState(title: title, progressText: "…")
        registry.start(state)
        registry.presented = nil
        return state
    }

    private func controlThatMustDisappear() -> LongOperationState {
        let control = start(title: "Control")
        control.isFinished = true
        registry.scheduleDismissal(of: control.id, after: 0.05)
        return control
    }

    private func wait(upTo seconds: TimeInterval = 20,
                      until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    func testAFinishedOperationClearsItselfFromTheBanner() async {
        let state = start(title: "Installing Vaultwarden")
        state.isFinished = true
        registry.scheduleDismissal(of: state.id, after: 0.05)
        let cleared = await wait { self.registry.entries.isEmpty }
        XCTAssertTrue(cleared, "the green line takes itself off")
    }

    func testAFailedOperationStays() async {
        let control = controlThatMustDisappear()
        let state = start(title: "Installing Immich")
        state.errorMessage = "the server refused"
        state.isFinished = true
        registry.scheduleDismissal(of: state.id, after: 0.05)

        let fired = await wait { !self.registry.entries.contains { $0.id == control.id } }
        XCTAssertTrue(fired, "the control operation proves the countdown ran")
        XCTAssertEqual(registry.entries.count, 1, "a failure is read after the fact, not while it happens")
        XCTAssertEqual(registry.entries.first?.id, state.id)
        // It can still be swiped away.
        registry.dismiss(state.id)
        XCTAssertTrue(registry.entries.isEmpty)
    }

    func testARunningOperationCannotBeDismissed() {
        let state = start(title: "Backing up Nextcloud")
        registry.dismiss(state.id)
        XCTAssertEqual(registry.entries.count, 1, "the banner is the only way back into it")
    }

    func testTheOperationBeingLookedAtIsNotTakenAway() async {
        let control = controlThatMustDisappear()
        let state = start(title: "Updating Forgejo")
        state.isFinished = true
        registry.present(state)
        registry.scheduleDismissal(of: state.id, after: 0.05)

        let fired = await wait { !self.registry.entries.contains { $0.id == control.id } }
        XCTAssertTrue(fired, "the control operation proves the countdown ran")
        XCTAssertEqual(registry.entries.count, 1, "its sheet is open; closing it is what clears it")
        XCTAssertEqual(registry.entries.first?.id, state.id)
    }
}
