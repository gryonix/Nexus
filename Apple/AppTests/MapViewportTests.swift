import XCTest
@testable import gryonixNexus

final class MapViewportTests: XCTestCase {
    private let content = CGSize(width: 2000, height: 1000)
    private let view = CGSize(width: 400, height: 200)

    private func viewport() -> MapViewport { MapViewport(content: content) }

    func testAPinchKeepsTheMapPointUnderTheFingers() {
        var viewport = viewport()
        let anchor = CGPoint(x: 320, y: 40)
        let before = viewport.mapPoint(for: anchor, in: view)
        viewport.zoom(by: 3, around: anchor, in: view)
        let after = viewport.mapPoint(for: anchor, in: view)
        XCTAssertEqual(before.x, after.x, accuracy: 0.001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.001)
        XCTAssertEqual(viewport.scale, 3, accuracy: 0.001)
    }

    func testTheVisibleRectNeverLeavesTheMap() {
        var viewport = viewport()
        viewport.zoom(by: 4, around: CGPoint(x: 0, y: 0), in: view)
        viewport.pan(by: CGSize(width: 10_000, height: 10_000), in: view)
        XCTAssertEqual(viewport.visible(in: view).minX, 0, accuracy: 0.001)
        XCTAssertEqual(viewport.visible(in: view).minY, 0, accuracy: 0.001)
        viewport.pan(by: CGSize(width: -10_000, height: -10_000), in: view)
        XCTAssertEqual(viewport.visible(in: view).maxX, content.width, accuracy: 0.001)
        XCTAssertEqual(viewport.visible(in: view).maxY, content.height, accuracy: 0.001)
    }

    func testZoomingOutStopsAtTheWholeMap() {
        var viewport = viewport()
        viewport.zoom(by: 0.1, around: CGPoint(x: 200, y: 100), in: view)
        XCTAssertEqual(viewport.scale, 1, accuracy: 0.001)
        XCTAssertEqual(viewport.visible(in: view), CGRect(origin: .zero, size: content))
        XCTAssertFalse(viewport.isZoomedIn)
    }

    func testATallViewShowsTheWholeMapAndThenFillsWithTheZoom() {
        let tall = CGSize(width: 400, height: 800)
        var viewport = viewport()
        let shown = viewport.visible(in: tall)
        XCTAssertEqual(shown.width, content.width, accuracy: 0.001)
        XCTAssertGreaterThan(shown.height, content.height)
        XCTAssertEqual(shown.midY, content.height / 2, accuracy: 0.001)

        viewport.zoom(by: 4, around: CGPoint(x: 200, y: 400), in: tall)
        let zoomed = viewport.visible(in: tall)
        XCTAssertLessThan(zoomed.width, content.width)
        XCTAssertLessThanOrEqual(zoomed.height, content.height)
        XCTAssertGreaterThanOrEqual(zoomed.minY, 0)
        XCTAssertLessThanOrEqual(zoomed.maxY, content.height + 0.001)
    }

    func testZoomingInStopsAtTheLimit() {
        var viewport = viewport()
        viewport.zoom(by: 1000, around: CGPoint(x: 200, y: 100), in: view)
        XCTAssertEqual(viewport.scale, MapViewport.maxScale, accuracy: 0.001)
    }

    func testATapZoomedInHitsTheCountryUnderTheFinger() throws {
        let map = WorldMap.shared
        var viewport = MapViewport(content: map.size)
        let germany = try XCTUnwrap(map.countries["DE"]).center
        let card = CGSize(width: 360, height: 360 / map.size.width * map.size.height)
        let middle = CGPoint(x: card.width / 2, y: card.height / 2)
        viewport.zoom(by: 6, around: middle, in: card)
        viewport.pan(by: CGSize(
            width: (viewport.mapPoint(for: middle, in: card).x - germany.x)
                * viewport.pointsPerUnit(in: card),
            height: (viewport.mapPoint(for: middle, in: card).y - germany.y)
                * viewport.pointsPerUnit(in: card)), in: card)
        let landed = viewport.mapPoint(for: middle, in: card)
        XCTAssertEqual(map.country(at: landed, tolerance: 1), "DE")
    }

    func testResetGoesBackToTheWholeWorld() {
        var viewport = viewport()
        viewport.zoom(by: 5, around: CGPoint(x: 50, y: 50), in: view)
        viewport.reset(in: view)
        XCTAssertEqual(viewport.visible(in: view), CGRect(origin: .zero, size: content))
    }
}
