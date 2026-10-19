import Combine
import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class ServerCardRedrawTests: XCTestCase {
    private let deployment = Deployment(name: "example.net",
                                        topology: .singleHost,
                                        entry: HostEndpoint(host: "203.0.113.10", user: "root"))

    private func sample(cpu: Double) -> ServerHostMetricsState {
        ServerHostMetricsState(snapshot: HostMetricsSnapshot(
            collectorRow: MetricsHistoryPoint(
                date: Date(timeIntervalSince1970: 1_000_000),
                cpuPercent: cpu, memUsedBytes: 512, memTotalBytes: 1024,
                diskUsedBytes: 10, diskTotalBytes: 100,
                netReceivedPerSecond: 1, netSentPerSecond: 1,
                diskReadPerSecond: 1, diskWrittenPerSecond: 1,
                load1: 0.2, temperatureCelsius: nil)))
    }

    private func card(_ state: ServerHostMetricsState) -> ServerMetricsCard {
        ServerMetricsCard(deployment: deployment, host: .vps, state: state)
    }

    // MARK: - (1) one server's sample must not touch another's box

    func testASampleOnlyReachesItsOwnDeploymentsBox() {
        let store = ServerMetricsStore()
        let other = UUID()
        let mine = store.card(for: deployment.id)
        let theirs = store.card(for: other)
        XCTAssertFalse(mine === theirs, "each deployment gets its own box, or one server's sample invalidates every card")

        XCTAssertTrue(store.card(for: deployment.id) === mine)
    }

    func testWritingAReadingAnnouncesTheBox() {
        let box = ServerMetricsStore().card(for: deployment.id)
        var announced = 0
        let watch = box.objectWillChange.sink { _ in announced += 1 }
        defer { watch.cancel() }

        box.record(sample(cpu: 12), for: .vps)

        XCTAssertEqual(announced, 1)
    }

    func testTheStorePublishesNothingAtAll() {
        let published = Mirror(reflecting: ServerMetricsStore()).children.filter {
            String(describing: type(of: $0.value)).hasPrefix("Published<")
        }
        XCTAssertTrue(published.isEmpty,
                      "ServerMetricsStore must publish nothing — found \(published.map { $0.label ?? "?" })")
    }

    // MARK: - (2) what the card calls equal

    func testACardHandedTheSameReadingTwiceIsEqual() {
        XCTAssertEqual(card(sample(cpu: 12)), card(sample(cpu: 12)))
    }

    func testEverythingTheCardDrawsMakesItUnequal() {
        XCTAssertNotEqual(card(ServerHostMetricsState()), card(sample(cpu: 12)),
                          "the first reading arriving is the whole point of the card")
        XCTAssertNotEqual(card(sample(cpu: 12)), card(sample(cpu: 13)),
                          "same shape, one number moved")

        var failed = sample(cpu: 12)
        failed.errorMessage = "unreachable"
        XCTAssertNotEqual(card(sample(cpu: 12)), card(failed),
                          "the failure rides alongside the last good snapshot and has to be drawn")

        var renamed = deployment
        renamed.name = "b.example.net"
        XCTAssertNotEqual(card(sample(cpu: 12)),
                          ServerMetricsCard(deployment: renamed, host: .vps, state: sample(cpu: 12)),
                          "the name is in the header")

        XCTAssertNotEqual(card(sample(cpu: 12)),
                          ServerMetricsCard(deployment: deployment, host: .home, state: sample(cpu: 12)),
                          "the host badge says which machine this is")

        XCTAssertNotEqual(card(sample(cpu: 12)),
                          ServerMetricsCard(deployment: deployment, host: .vps,
                                            state: sample(cpu: 12), embedded: true),
                          "an embedded card draws no surface of its own")
    }

    func testTheTwoMachineCardComparesEveryMachine() {
        func combined(_ vps: Double, _ home: Double) -> CombinedServerCard {
            CombinedServerCard(deployment: deployment,
                               machines: [(host: .vps, state: sample(cpu: vps)),
                                          (host: .home, state: sample(cpu: home))])
        }
        XCTAssertEqual(combined(1, 2), combined(1, 2))
        XCTAssertNotEqual(combined(1, 2), combined(1, 3), "the second machine moved")
        XCTAssertNotEqual(combined(1, 2), combined(9, 2), "the first machine moved")
        XCTAssertNotEqual(
            combined(1, 2),
            CombinedServerCard(deployment: deployment,
                               machines: [(host: .vps, state: sample(cpu: 1))]),
            "a machine disappearing is a different card")
    }
}
