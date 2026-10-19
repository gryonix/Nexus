import ServerControl
import SwiftUI
import XCTest

@testable import gryonixNexus

final class ServerCardLayoutTests: XCTestCase {
    /// Named servers so a failure says which one moved
    private func fleet(_ sizes: [ServerCardSize?]) -> [Deployment] {
        sizes.enumerated().map { index, size in
            var deployment = Deployment(
                name: "server-\(index)",
                topology: .singleHost,
                domain: "example-\(index).test",
                entry: HostEndpoint(host: "203.0.113.\(index + 1)", user: "root"))
            deployment.cardSize = size
            return deployment
        }
    }

    private func names(_ rows: [ServerCardLayout.Row]) -> [[[String]]] {
        rows.map { $0.columns.map { $0.map(\.name) } }
    }

    private func twoMachine(_ name: String) -> Deployment {
        var deployment = Deployment(
            name: name,
            topology: .vpsRelayWithHomeBackend,
            domain: "\(name).test",
            entry: HostEndpoint(host: "203.0.113.200", user: "root"),
            homeWGAddress: "10.8.0.2")
        deployment.cardSize = .compact
        return deployment
    }

    // MARK: - The default

    func testAServerWithNoChoiceFollowsTheAppDefault() {
        let unset = fleet([nil])[0]
        XCTAssertEqual(ServerCardLayout.size(of: unset, whenUnset: .wide), .wide)
        XCTAssertEqual(ServerCardLayout.size(of: unset, whenUnset: .compact), .compact)
    }

    func testAServerWithAChoiceIgnoresTheAppDefault() {
        let wide = fleet([.wide])[0]
        let compact = fleet([.compact])[0]
        XCTAssertEqual(ServerCardLayout.size(of: wide, whenUnset: .compact), .wide)
        XCTAssertEqual(ServerCardLayout.size(of: compact, whenUnset: .wide), .compact)
    }

    func testAFleetThatChoseNothingIsUnchangedByTheFeature() {
        let servers = fleet([nil, nil, nil])
        XCTAssertEqual(names(ServerCardLayout.rows(of: servers, whenUnset: .wide)),
                       [[["server-0"]], [["server-1"]], [["server-2"]]])
        XCTAssertEqual(names(ServerCardLayout.rows(of: servers, whenUnset: .compact)),
                       [[["server-0"], ["server-1"]], [["server-2"]]])
    }

    // MARK: - The flow

    func testAShrunkenCardIsJoinedByTheNextNarrowOneWithoutMovingTheWideOnes() {
        let servers = fleet([.wide, .compact, .wide, .compact, .wide])
        let rows = ServerCardLayout.rows(of: servers, whenUnset: .wide)
        XCTAssertEqual(names(rows),
                       [[["server-0"]], [["server-1"], ["server-3"]],
                        [["server-2"]], [["server-4"]]])
        let wideRows = rows.enumerated().filter { $0.element.all.count == 1 }
            .filter { $0.element.all[0].cardSize == .wide }
        XCTAssertEqual(wideRows.map(\.offset), [0, 2, 3])
        XCTAssertEqual(wideRows.map { $0.element.all[0].name }, ["server-0", "server-2", "server-4"])
    }

    func testAnOddNarrowCardEndsUpAloneOnItsRow() {
        let rows = ServerCardLayout.rows(of: fleet([.compact, .compact, .compact]),
                                         whenUnset: .wide)
        XCTAssertEqual(names(rows), [[["server-0"], ["server-1"]], [["server-2"]]])
    }

    func testAWideCardBetweenTwoNarrowOnesDoesNotBreakThePair() {
        let rows = ServerCardLayout.rows(of: fleet([.compact, .wide, .compact]),
                                         whenUnset: .wide)
        XCTAssertEqual(names(rows), [[["server-0"], ["server-2"]], [["server-1"]]])
    }

    func testARowNeverHoldsMoreThanTwo() {
        let rows = ServerCardLayout.rows(of: fleet([.compact, .compact, .compact, .compact]),
                                         whenUnset: .wide)
        XCTAssertEqual(names(rows), [[["server-0"], ["server-1"]],
                                     [["server-2"], ["server-3"]]])
        XCTAssertTrue(rows.allSatisfy { $0.columns.count <= 2 })
        XCTAssertTrue(rows.allSatisfy { $0.columns.allSatisfy { $0.count == 1 } })
    }

    func testEveryServerAppearsExactlyOnce() {
        let servers = fleet([.wide, .compact, nil, .compact, .wide, .compact, nil])
        for fallback in ServerCardSize.allCases {
            let drawn = ServerCardLayout.rows(of: servers, whenUnset: fallback).flatMap(\.all)
            XCTAssertEqual(drawn.count, servers.count,
                           "fallback \(fallback.rawValue) changed how many cards are drawn")
            XCTAssertEqual(Set(drawn.map(\.id)), Set(servers.map(\.id)),
                           "fallback \(fallback.rawValue) changed the fleet")
        }
    }

    func testAThreeMachineCardIsThreeSlotsTall() {
        var deployment = Deployment(name: "three", topology: .vpsRelayWithHomeBackend,
                                    entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                                    homeWGAddress: "10.8.0.2", cardSize: .compact)
        XCTAssertEqual(ServerCardLayout.slots(of: deployment), 2)

        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: deployment.ingressNode?.id)
        deployment.storedNodes = deployment.derivedNodes + [extra]

        XCTAssertEqual(ServerCardLayout.slots(of: deployment), 3,
                       "counted short, the column beside it is packed for a card that is taller")
    }

    func testThreeOrdinaryCardsFitBesideAThreeMachineOne() {
        var tall = Deployment(name: "three", topology: .vpsRelayWithHomeBackend,
                              entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                              homeWGAddress: "10.8.0.2", cardSize: .compact)
        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: tall.ingressNode?.id)
        tall.storedNodes = tall.derivedNodes + [extra]
        let ordinary = (1...3).map {
            Deployment(name: "n\($0)", topology: .singleHost,
                       entry: HostEndpoint(host: "203.0.113.\($0)", user: "root"),
                       cardSize: .compact)
        }

        let rows = ServerCardLayout.rows(of: [tall] + ordinary, whenUnset: .wide)
        XCTAssertEqual(rows.count, 1, "all four belong to one row: \(rows.map(\.all.count))")
        let loads = rows[0].columns.map { $0.reduce(0) { $0 + ServerCardLayout.slots(of: $1) } }
        XCTAssertEqual(loads, [3, 3])
    }

    func testTwoOrdinaryCardsFitBesideATwoMachineOne() {
        let tall = twoMachine("pair")
        var servers = fleet([.compact, .compact])
        servers.insert(tall, at: 0)
        let rows = ServerCardLayout.rows(of: servers, whenUnset: .wide)
        XCTAssertEqual(names(rows), [[["pair"], ["server-0", "server-1"]]])
        XCTAssertEqual(ServerCardLayout.slots(of: tall), 2)
        XCTAssertEqual(rows[0].columns.map { $0.reduce(0) { $0 + ServerCardLayout.slots(of: $1) } },
                       [2, 2])
    }

    func testAnOrdinaryCardComesUpToFillTheRoomATallCardMade() {
        var servers = fleet([.compact, .wide, .compact])
        servers.insert(twoMachine("pair"), at: 1)
        let rows = ServerCardLayout.rows(of: servers, whenUnset: .wide)
        XCTAssertEqual(names(rows), [[["server-0", "server-2"], ["pair"]],
                                     [["server-1"]]])
    }

    func testTwoTallCardsFillARowByThemselves() {
        let rows = ServerCardLayout.rows(of: [twoMachine("a"), twoMachine("b"), twoMachine("c")],
                                         whenUnset: .wide)
        XCTAssertEqual(names(rows), [[["a"], ["b"]], [["c"]]])
    }

    func testTheDemoFleetFillsTheTallCardsColumn() {
        var servers = DemoServer.deployments()
        XCTAssertGreaterThanOrEqual(servers.count, 4, "the demo fleet shrank")
        for index in servers.indices { servers[index].cardSize = .compact }
        let tall = servers.firstIndex { ServerCardLayout.slots(of: $0) == 2 }
        XCTAssertNotNil(tall, "the demo fleet no longer has a two-machine server")
        let rows = ServerCardLayout.rows(of: servers, whenUnset: .wide)
        let row = rows[0]
        XCTAssertEqual(row.columns.count, 2)
        let slots = row.columns.map { $0.reduce(0) { $0 + ServerCardLayout.slots(of: $1) } }
        XCTAssertEqual(slots, [2, 2])
        XCTAssertEqual(row.columns.map(\.count).sorted(), [1, 2])
    }

    // MARK: - The width a card is drawn at

    func testTheNarrowCardIsHalfTheRowLessTheGutter() {
        let servers = fleet([.compact, .wide])
        let narrow = ServerCardLayout.cellWidth(of: servers[0], listWidth: 440,
                                                inset: ServerListView.rowInset,
                                                gutter: ServerListView.columnGutter,
                                                whenUnset: .wide)
        let wide = ServerCardLayout.cellWidth(of: servers[1], listWidth: 440,
                                              inset: ServerListView.rowInset,
                                              gutter: ServerListView.columnGutter,
                                              whenUnset: .wide)
        XCTAssertEqual(wide, 440 - ServerListView.rowInset * 2)
        XCTAssertEqual((narrow ?? 0) * 2 + ServerListView.columnGutter, wide)
    }

    func testTheWidthFollowsTheServersOwnSizeAndThenTheDefault() {
        let servers = fleet([nil])
        let widths = ServerCardSize.allCases.map { fallback in
            ServerCardLayout.cellWidth(of: servers[0], listWidth: 440,
                                       inset: ServerListView.rowInset,
                                       gutter: ServerListView.columnGutter,
                                       whenUnset: fallback)
        }
        XCTAssertEqual(Set(widths).count, 2, "the app default stopped deciding: \(widths)")
    }

    func testAnUnmeasuredListHasNoWidthToHandOver() {
        let servers = fleet([.compact])
        for listWidth in [nil, 0, 20, CGFloat.nan] as [CGFloat?] {
            XCTAssertNil(ServerCardLayout.cellWidth(of: servers[0], listWidth: listWidth,
                                                    inset: ServerListView.rowInset,
                                                    gutter: ServerListView.columnGutter,
                                                    whenUnset: .wide),
                         "a list \(String(describing: listWidth))pt wide gave a width")
        }
    }
}
