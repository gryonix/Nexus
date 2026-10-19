import ServerControl
import XCTest
@testable import gryonixNexus

@MainActor
final class AgentUpdateOfferTests: XCTestCase {
    private func server(_ name: String) -> Deployment {
        Deployment(name: name, topology: .singleHost, entry: HostEndpoint(host: "198.51.100.1", user: "root"))
    }

    private func offerModel(_ servers: [Deployment], deadline: Duration = .seconds(5),
                            ready: @escaping AgentUpdateOffer.Ready = { true },
                            probe: @escaping AgentUpdateOffer.Probe) -> AgentUpdateOffer {
        AgentUpdateOffer(fleet: { servers }, probe: probe, ready: ready, deadline: deadline,
                         retryDelay: .milliseconds(50), presentWithin: .milliseconds(100))
    }

    /// The window is up: the sheet's own onAppear
    private func waitForOffer(_ model: AgentUpdateOffer, showing: Bool = true) async {
        for _ in 0..<100 where model.offer == nil { try? await Task.sleep(for: .milliseconds(20)) }
        if showing, let offer = model.offer { model.appeared(offer) }
    }

    func testAnOutdatedServerGetsAnOfferAtLaunch() async {
        let old = server("old")
        let model = offerModel([old, server("fresh")]) { deployment, _ in
            deployment.id == old.id
                ? .outdated(.init(deployment: deployment, installed: "0.0.100", target: "0.0.200")) : .current
        }

        await model.checkOnLaunch()
        await waitForOffer(model)

        XCTAssertEqual(model.offer?.servers.map(\.deployment.name), ["old"])
        XCTAssertEqual(model.findings[old.id]?.outdated?.target, "0.0.200")
    }

    func testNothingIsOfferedWhenEveryAgentIsCurrent() async {
        let model = offerModel([server("a")]) { _, _ in .current }
        await model.checkOnLaunch()
        XCTAssertNil(model.offer)
    }

    func testLaterSilencesTheOfferOnlyUntilTheNextStart() async {
        let old = server("old")
        let probe: AgentUpdateOffer.Probe = { deployment, _ in
            .outdated(.init(deployment: deployment, installed: "0.0.100", target: "0.0.200"))
        }
        let model = offerModel([old], probe: probe)
        await model.checkOnLaunch()
        await waitForOffer(model)
        model.later()
        await model.checkOnLaunch()
        XCTAssertNil(model.offer, "no second window while the app stays open")

        model.appLeft()
        await model.checkOnLaunch()
        await waitForOffer(model)
        XCTAssertNotNil(model.offer, "opening the app again asks again, even soon after")
    }

    func testAnOfferNobodySawIsShownAgain() async {
        let old = server("old")
        let model = offerModel([old]) { deployment, _ in
            .outdated(.init(deployment: deployment, installed: "0.0.100", target: "0.0.200"))
        }
        await model.checkOnLaunch()
        await waitForOffer(model, showing: false)
        for _ in 0..<100 where model.offer != nil { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(model.offer, "another window held ours back")

        await waitForOffer(model)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(model.offer, "once seen, the window stays")
    }

    func testServersWaitForTheLicence() async {
        let old = server("old")
        let licensed = Counter()
        let model = offerModel([old], ready: { licensed.bump(); return licensed.value > 2 }) { deployment, _ in
            .outdated(.init(deployment: deployment, installed: "0.0.100", target: "0.0.200"))
        }
        await model.checkOnLaunch()
        XCTAssertNil(model.offer)
        await waitForOffer(model)
        XCTAssertEqual(model.offer?.servers.map(\.deployment.name), ["old"])
    }

    func testAServerThatNeverAnswersDoesNotHoldTheWindowBack() async {
        let old = server("old")
        let stuck = server("stuck")
        let model = offerModel([old, stuck], deadline: .milliseconds(300)) { deployment, _ in
            if deployment.id == stuck.id {
                try? await Task.sleep(for: .seconds(30))
                return .current
            }
            return .outdated(.init(deployment: deployment, installed: "0.0.100", target: "0.0.200"))
        }

        let started = Date()
        await model.checkOnLaunch()
        await waitForOffer(model)

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(model.offer?.servers.map(\.deployment.name), ["old"])
        if case .unreachable(let reason) = model.findings[stuck.id] {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("the silent server is reported")
        }
    }

    func testTheWindowOpensBeforeASlowServerAnswers() async {
        let old = server("old")
        let slow = server("slow")
        let model = offerModel([old, slow], deadline: .seconds(20)) { deployment, _ in
            if deployment.id == slow.id {
                try? await Task.sleep(for: .seconds(10))
                return .current
            }
            return .outdated(.init(deployment: deployment, installed: "0.0.100", target: "0.0.200"))
        }

        let check = Task { await model.checkOnLaunch() }
        await waitForOffer(model)

        XCTAssertEqual(model.offer?.servers.map(\.deployment.name), ["old"])
        check.cancel()
    }

    func testReturningToTheAppSoonAfterDoesNotAskTheServersAgain() async {
        let counter = Counter()
        let model = offerModel([server("a")]) { _, _ in
            counter.bump()
            return .current
        }
        await model.checkOnLaunch()
        await model.checkOnLaunch()
        XCTAssertEqual(counter.value, 1)
    }

    func testAServerThatCouldNotBeReachedAtStartIsTriedAgain() async {
        let old = server("old")
        let counter = Counter()
        let model = offerModel([old]) { deployment, _ in
            counter.bump()
            return counter.value < 3
                ? .unreachable("down") : .outdated(.init(deployment: deployment, installed: "0.0.100", target: "0.0.200"))
        }

        await model.checkOnLaunch()
        XCTAssertNil(model.offer, "the first try found nothing")
        await waitForOffer(model)

        XCTAssertEqual(model.offer?.servers.map(\.deployment.name), ["old"])
        XCTAssertEqual(model.offer?.version, "0.0.200")
    }

    func testTheOfferNamesTheNewestVersionAmongTheServers() async {
        let one = server("one")
        let two = server("two")
        let model = offerModel([one, two]) { deployment, _ in
            .outdated(.init(deployment: deployment, installed: "0.0.1",
                            target: deployment.id == one.id ? "0.0.5" : "0.0.9", source: .published))
        }
        await model.checkOnLaunch()
        await waitForOffer(model)
        XCTAssertEqual(model.offer?.version, "0.0.9")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
}
