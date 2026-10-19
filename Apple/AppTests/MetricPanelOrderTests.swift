import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class MetricPanelOrderTests: XCTestCase {
    private var store: MetricPanelStore!
    private var defaults: UserDefaults!
    private let alpha = UUID()
    private let beta = UUID()

    override func setUp() async throws {
        try await super.setUp()
        let name = "MetricPanelOrderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)
        defaults.removePersistentDomain(forName: name)
        store = MetricPanelStore(defaults: defaults)
    }

    private func seed() -> [MetricPanel] {
        let panels = [
            MetricPanel(deploymentID: alpha, host: .vps, metrics: [.cpu], range: .hour),
            MetricPanel(deploymentID: beta, host: .vps, metrics: [.memory], range: .hour),
            MetricPanel(deploymentID: alpha, host: .vps, metrics: [.disk], range: .day),
            MetricPanel(deploymentID: beta, host: .vps, metrics: [.network], range: .day)
        ]
        for panel in panels { store.add(panel) }
        return panels
    }

    func testMovingAPanelDownRewritesTheWholeBoard() {
        let panels = seed()
        var ordered = store.panels
        ordered.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        store.reorder(ordered)

        XCTAssertEqual(store.panels.map(\.id),
                       [panels[1].id, panels[2].id, panels[0].id, panels[3].id])
    }

    func testReorderingOneServersPanelsLeavesTheOthersWhereTheyAre() {
        let panels = seed()
        var mine = store.panels.filter { $0.deploymentID == alpha }
        mine.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        store.reorder(mine)

        XCTAssertEqual(store.panels.map(\.id),
                       [panels[2].id, panels[1].id, panels[0].id, panels[3].id])
    }

    func testAPartialOrderIsRefused() {
        let panels = seed()
        store.reorder([panels[3], panels[1]])
        XCTAssertEqual(store.panels.map(\.id),
                       [panels[0].id, panels[3].id, panels[2].id, panels[1].id])

        // A panel the board has never seen: nothing moves.
        let stranger = MetricPanel(deploymentID: alpha, host: .vps, metrics: [.load], range: .hour)
        let before = store.panels.map(\.id)
        store.reorder([stranger, panels[0]])
        XCTAssertEqual(store.panels.map(\.id), before)
    }

    func testDeletingFromTheSubsetRemovesOnlyThatPanel() {
        let panels = seed()
        store.remove(panels[2])
        XCTAssertEqual(store.panels.map(\.id),
                       [panels[0].id, panels[1].id, panels[3].id])
    }

    func testTheOrderIsPersisted() {
        let panels = seed()
        var ordered = store.panels
        ordered.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        store.reorder(ordered)

        let reloaded = MetricPanelStore(defaults: defaults)
        XCTAssertEqual(reloaded.panels.map(\.id),
                       [panels[3].id, panels[0].id, panels[1].id, panels[2].id])
    }
}
