import XCTest
@testable import ServerControl

final class ServerProblemsTests: XCTestCase {
    func testEachFactMapsToItsProblem() {
        let id = UUID()
        XCTAssertEqual(ServerHealthFacts(id: id, unreachable: true).problems, [.unreachable])
        XCTAssertEqual(ServerHealthFacts(id: id, diskFraction: 0.9).problems, [.diskAlmostFull])
        XCTAssertEqual(ServerHealthFacts(id: id, diskFraction: 0.89).problems, [])
        XCTAssertEqual(ServerHealthFacts(id: id, servicesDown: 2).problems, [.serviceDown])
        XCTAssertEqual(ServerHealthFacts(id: id, updatesPending: 5).problems, [.updatesPending])
        XCTAssertEqual(ServerHealthFacts(id: id, servicesDown: 0, updatesPending: 0).problems, [])
    }

    func testCountsAndFilter() {
        let a = ServerHealthFacts(id: UUID(), unreachable: true)
        let b = ServerHealthFacts(id: UUID(), diskFraction: 0.95, updatesPending: 3)
        let c = ServerHealthFacts(id: UUID(), diskFraction: 0.2)
        let counts = ServerProblems.counts([a, b, c])
        XCTAssertEqual(counts[.unreachable], 1)
        XCTAssertEqual(counts[.diskAlmostFull], 1)
        XCTAssertEqual(counts[.updatesPending], 1)
        XCTAssertNil(counts[.serviceDown])
        XCTAssertEqual(ServerProblems.ids(with: .diskAlmostFull, in: [a, b, c]), [b.id])
    }

    func testOfflineServersSinkKeepingOrder() {
        let order = ["a", "b", "c", "d", "e"]
        let offline: Set<String> = ["b", "d"]
        XCTAssertEqual(ServerListOrdering.ordered(order) { offline.contains($0) }, ["a", "c", "e", "b", "d"])
        XCTAssertEqual(ServerListOrdering.ordered(order) { _ in false }, order)
    }
}
