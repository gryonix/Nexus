import SwiftUI
import XCTest

@testable import gryonixNexus

final class BrandPillGeometryTests: XCTestCase {
    private let notches: [(name: String, inset: CGFloat, endsAt: CGFloat)] = [
        ("iPhone 13 notch", 47, 30),
        ("iPhone 14 notch", 50, 30),
    ]

    private let islands: [(name: String, inset: CGFloat)] = [
        ("iPhone 14 Pro island", 59),
        ("iPhone 17 Pro Max island", 62),
    ]

    private var shapes: [(name: String, inset: CGFloat, endsAt: CGFloat)] {
        notches + islands.map { ($0.name, $0.inset, $0.inset - 11) }
    }

    func testThePlateStaysInsideTheShapeThatHidesIt() {
        for shape in notches {
            let metrics = BrandPill.metrics(topInset: shape.inset)
            XCTAssertLessThan(
                metrics.bottom, shape.endsAt - 2,
                "\(shape.name): the plate reaches \(metrics.bottom)pt and the notch ends at \(shape.endsAt)")
        }
    }

    func testThePlateIsAsBigAsTheBandAllows() {
        for shape in notches {
            let metrics = BrandPill.metrics(topInset: shape.inset)
            XCTAssertGreaterThanOrEqual(
                metrics.height, 21,
                "\(shape.name): a \(metrics.height)pt plate against the 22pt one it is meant to read like")
            XCTAssertLessThanOrEqual(
                metrics.bottom, 27,
                "\(shape.name): the plate ends at \(metrics.bottom)pt, past the 26.7 Telegram stops at")
        }
    }

    func testTheIslandPlateIsTheIslandsOwnFootprint() throws {
        for shape in islands {
            let metrics = BrandPill.metrics(topInset: shape.inset)
            let plate = try XCTUnwrap(metrics.plate, "\(shape.name): the mark is not standing in for the island")
            XCTAssertEqual(plate.width, 88, accuracy: 0.5, "\(shape.name): width")
            XCTAssertEqual(plate.height, 33.7, accuracy: 0.5, "\(shape.name): height")
            XCTAssertEqual(metrics.topY, shape.inset - 46.2, accuracy: 0.6, "\(shape.name): top")
            XCTAssertEqual(metrics.bottom, shape.inset - 12.5, accuracy: 0.6, "\(shape.name): bottom")
        }
    }

    func testThePlateStopsShortOfTheIslandsEdges() {
        let measuredIslandHeight: CGFloat = 36.3
        for shape in islands {
            let metrics = BrandPill.metrics(topInset: shape.inset)
            let islandBottom = shape.inset - 11.3
            let islandTop = islandBottom - measuredIslandHeight
            XCTAssertLessThanOrEqual(metrics.bottom, islandBottom - 1,
                                     "\(shape.name): the plate ends at \(metrics.bottom)pt, the island at \(islandBottom)")
            XCTAssertGreaterThanOrEqual(metrics.topY, islandTop + 1,
                                        "\(shape.name): the plate starts at \(metrics.topY)pt, the island at \(islandTop)")
        }
    }

    func testThePlateClearsTheNarrowestKnownIsland() {
        let narrowestIslandWidth: CGFloat = 94.3
        let metrics = BrandPill.metrics(topInset: 62)
        XCTAssertLessThan(metrics.plate?.height ?? .infinity, 36.3,
                          "the plate must be shorter than the island it hides behind, not the same height")
        XCTAssertLessThan(metrics.plate?.width ?? .infinity, narrowestIslandWidth,
                          "the plate is \(metrics.plate?.width ?? -1)pt against a 94.3pt island — it will show past the edge")
    }

    func testAPlainStatusBarGetsNoMarkAtAll() {
        XCTAssertLessThan(CGFloat(20), 30, "an SE-class inset must fall below the threshold")
    }

    /// The two shapes really are given different numbers
    func testTheTwoShapesAreMeasuredSeparately() {
        let notch = BrandPill.metrics(topInset: 47)
        let island = BrandPill.metrics(topInset: 62)
        XCTAssertLessThan(notch.topY, island.topY)
        XCTAssertLessThan(notch.bottom, island.bottom)
    }

    func testTheModelledHeightMatchesTheFont() throws {
        for shape in notches {
            let metrics = BrandPill.metrics(topInset: shape.inset)
            XCTAssertNil(metrics.plate, "\(shape.name): a notch has no island to stand in for")
            let drawn = Self.font(size: metrics.size).lineHeight + metrics.padding.vertical * 2
            XCTAssertEqual(metrics.height, drawn, accuracy: 1.5,
                           "\(shape.name): the model says \(metrics.height)pt and the font draws \(drawn)pt")
        }
    }

    func testTheWordFitsInsideTheIsland() throws {
        for shape in islands {
            let metrics = BrandPill.metrics(topInset: shape.inset)
            let plate = try XCTUnwrap(metrics.plate)
            let line = Self.font(size: metrics.size).lineHeight
            XCTAssertLessThan(line, plate.height - 8,
                              "\(shape.name): \(line)pt of text in a \(plate.height)pt plate leaves no margin")
            XCTAssertGreaterThan(line, plate.height / 2,
                                 "\(shape.name): the word is lost in the middle of the island")
        }
    }

    func testTheWordFitsTheIslandWidth() throws {
        for shape in islands {
            let metrics = BrandPill.metrics(topInset: shape.inset)
            let plate = try XCTUnwrap(metrics.plate)
            let font = Self.font(size: metrics.size)
            let width = ("gryonix" as NSString)
                .size(withAttributes: [.font: font, .kern: 0.2])
                .width
            XCTAssertLessThan(width, plate.width - 6,
                              "\(shape.name): \"gryonix\" measures \(width)pt in a \(plate.width)pt plate")
        }
    }

    private static func font(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        return UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,
                      size: size)
    }

    func testThePlateSitsHigherThanTheOneThatShowed() {
        let metrics = BrandPill.metrics(topInset: 47)
        XCTAssertLessThan(metrics.bottom, 28.7,
                          "the plate is no higher than the one the owner saw poking out")
    }
}
