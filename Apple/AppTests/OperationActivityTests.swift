import XCTest
@testable import gryonixNexus

final class OperationActivityTests: XCTestCase {
    private var appleRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func state(progress: String = "", finished: Bool = false,
                       error: String? = nil,
                       fraction: Double? = nil) -> OperationActivityAttributes.ContentState {
        .init(progressText: progress, isFinished: finished, errorMessage: error,
              progress: fraction)
    }

    // MARK: - The outcome

    func testAFinishedRunWithAnErrorIsAFailureNotASuccess() {
        XCTAssertEqual(OperationPresentation.outcome(state(finished: true, error: "boom")), .failed)
        XCTAssertEqual(OperationPresentation.outcome(state(finished: true)), .succeeded)
        XCTAssertEqual(OperationPresentation.outcome(state()), .running)
        XCTAssertEqual(OperationPresentation.outcome(state(error: "boom")), .failed)
    }

    func testEachOutcomeHasItsOwnSymbolAndTint() {
        let outcomes: [OperationPresentation.Outcome] = [.running, .succeeded, .failed]
        let symbols = outcomes.map(OperationPresentation.symbol)
        XCTAssertEqual(Set(symbols).count, outcomes.count,
                       "two outcomes drawn with one symbol are one outcome on screen")
        let tints = outcomes.map(OperationPresentation.tint)
        XCTAssertEqual(Set(tints.map(String.init(describing:))).count, outcomes.count,
                       "two outcomes drawn in one colour are one outcome on screen")
    }

    // MARK: - The detail line

    func testTheDetailLineCarriesTheFailure() {
        XCTAssertEqual(OperationPresentation.detail(state(progress: "Pulling images",
                                                          finished: true,
                                                          error: "no space left on device")),
                       "no space left on device",
                       "the failure is the whole reason to look at this afterwards")
    }

    func testAFinishedRunNeverGoesBlank() {
        XCTAssertEqual(OperationPresentation.detail(state(progress: "Restarted 3 containers",
                                                          finished: true)),
                       "Restarted 3 containers")
        XCTAssertFalse(OperationPresentation.detail(state(finished: true)).isEmpty,
                       "a finished run with nothing narrated still has to say something")
    }

    /// The clock must stop at the end
    func testTheClockStopsWhenTheRunDoes() {
        XCTAssertTrue(OperationPresentation.showsRunningClock(state(progress: "Pulling")))
        XCTAssertFalse(OperationPresentation.showsRunningClock(state(finished: true)))
        XCTAssertFalse(OperationPresentation.showsRunningClock(state(error: "boom")))
    }

    // MARK: - The bar

    func testTheBarAppearsOnlyForARunThatCountsItsSteps() {
        XCTAssertNil(OperationPresentation.barValue(state(progress: "Pulling images")),
                     "a run with nothing to count drew a bar")
        XCTAssertEqual(OperationPresentation.barValue(state(fraction: 0.4)), 0.4)
    }

    /// The bar goes at the end, both ways
    func testTheBarGoesWhenTheRunEnds() {
        XCTAssertNil(OperationPresentation.barValue(state(finished: true, fraction: 1)))
        XCTAssertNil(OperationPresentation.barValue(state(error: "boom", fraction: 0.6)))
    }

    func testTheBarIsClampedAndRefusesNonsense() {
        XCTAssertEqual(OperationPresentation.barValue(state(fraction: 1.4)), 1)
        XCTAssertEqual(OperationPresentation.barValue(state(fraction: -0.2)), 0)
        XCTAssertNil(OperationPresentation.barValue(state(fraction: .nan)))
        XCTAssertEqual(OperationPresentation.barValue(state(fraction: .infinity)), nil)
    }

    // MARK: - The card nobody can update

    func testARunningCardIsGivenADateAfterWhichItIsStale() throws {
        let code = try codeWithoutComments("App/Services/OperationActivities.swift")
        XCTAssertTrue(code.contains("staleDate: staleDate"),
                      "a running card is published with no staleDate, so a frozen line keeps "
                      + "looking current")
        XCTAssertTrue(code.contains("staleDate: nil"),
                      "the finished card is marked stale like a running one")
        XCTAssertGreaterThan(OperationActivities.staleAfter, 120,
                             "shorter than the quiet gap of an ordinary docker pull: every "
                             + "narrating run would look abandoned")
        XCTAssertLessThan(OperationActivities.staleAfter, 1800,
                          "long enough that the card this exists for never reaches it")
    }

    /// And the widget has to say so
    func testTheWidgetSaysWhyACardStopped() throws {
        let widget = try codeWithoutComments("Widgets/Extension/OperationLiveActivity.swift")
        XCTAssertTrue(widget.contains("context.isStale"),
                      "the lock screen ignores staleness, so the sentence is never shown")
        XCTAssertFalse(OperationPresentation.staleNote().isEmpty)
    }

    // MARK: - Every live process, not one of four

    func testAllFourSourcesRaiseACard() throws {
        for source in ["App/Features/Dashboard/RunningOperationsRegistry.swift",
                       "App/Features/Install/InstallSession.swift",
                       "App/Services/PendingAgentInstalls.swift",
                       "App/Features/Servers/ReinstallFlowView.swift"] {
            let code = try codeWithoutComments(source)
            XCTAssertTrue(code.contains("OperationActivities.shared.start("),
                          "\(source) never puts its run on the lock screen")
            XCTAssertTrue(code.contains("OperationActivities.shared.end("),
                          "\(source) raises a card it never takes down — it would count up for ever")
        }
    }

    /// One install, one card
    func testTheNarratedCardTakesOverFromTheRememberedOne() throws {
        let registry = try codeWithoutComments(
            "App/Features/Dashboard/RunningOperationsRegistry.swift")
        XCTAssertTrue(registry.contains("PendingAgentInstalls.shared.yieldLockScreen("),
                      "a watched run raises a second card beside the remembered one")
    }

    // MARK: - The sweep that ate its own cards

    func testTheOrphanSweepAsksAgainForEveryCardItLooksAt() throws {
        let code = try codeWithoutComments("App/Services/OperationActivities.swift")
        guard let start = code.range(of: "func endOrphans()"),
              let end = code.range(of: "\n    }", range: start.upperBound..<code.endIndex) else {
            XCTFail("endOrphans is gone or renamed")
            return
        }
        let body = String(code[start.upperBound..<end.lowerBound])
        XCTAssertTrue(body.contains("live.values.contains"),
                      "the sweep decides ownership from something other than the live cards, "
                      + "read at the moment it is about to end one")
        XCTAssertFalse(body.contains("let mine"),
                       "the owned set is captured before the hop again — a card created after "
                       + "that capture is ended the instant it is made")
    }

    // MARK: - The declarations without which none of it appears

    func testLiveActivitiesAreDeclaredInTheInfoPlist() throws {
        let manifest = try String(contentsOf: appleRoot.appendingPathComponent("project.yml"),
                                  encoding: .utf8)
        XCTAssertTrue(manifest.contains("NSSupportsLiveActivities: true"),
                      "the app does not declare Live Activities, so none can start")
    }

    @MainActor
    func testTheIslandKeepsTheOutcomeAtLeastAsLongAsTheBanner() {
        XCTAssertGreaterThanOrEqual(OperationActivities.finishedLingerSeconds,
                                    RunningOperationsRegistry.doneLingerSeconds,
                                    "the island would drop the outcome before the app's own banner does")
    }

    private func codeWithoutComments(_ relative: String) throws -> String {
        let text = try String(contentsOf: appleRoot.appendingPathComponent(relative),
                              encoding: .utf8)
        let code = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.isEmpty, "\(relative) was not read")
        return code
    }

    func testAFailureIsNotDismissedOnATimer() throws {
        let source = try codeWithoutComments("App/Services/OperationActivities.swift")
        XCTAssertTrue(source.contains("errorMessage == nil"),
                      "the dismissal policy does not distinguish a failure from a success")
    }

    /// The run's machine reaches the card
    func testTheRunsMachineReachesTheCard() throws {
        let watcher = try String(
            contentsOf: appleRoot.appendingPathComponent("App/Services/RunningJobsWatcher.swift"),
            encoding: .utf8)
        let dashboard = try String(
            contentsOf: appleRoot.appendingPathComponent("App/Features/Dashboard/DashboardViewModel.swift"),
            encoding: .utf8)
        XCTAssertFalse(watcher.contains("adopt(state)\n"),
                       "an adopted run reaches the lock screen without naming its machine")
        XCTAssertTrue(watcher.contains("serverName: deployment.name"),
                      "the watcher does not pass the machine name")
        XCTAssertTrue(dashboard.contains("serverName: deployment.name"),
                      "the dashboard does not pass the machine name")
    }
}
