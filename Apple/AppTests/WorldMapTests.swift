import XCTest
@testable import gryonixNexus

final class WorldMapTests: XCTestCase {
    private let map = WorldMap.shared

    func testEveryPickableCountryHasAShapeOrADot() {
        let missing = CountryCatalog.allCodes.filter { map.countries[$0] == nil }
        XCTAssertTrue(missing.isEmpty, "no map entry for \(missing)")
    }

    func testATapOnACountrysMiddleFindsThatCountry() throws {
        for code in ["DE", "BR", "RU", "AU", "US"] {
            let country = try XCTUnwrap(map.countries[code])
            XCTAssertEqual(map.country(at: country.center, tolerance: 1), code)
        }
    }

    func testCrimeaIsDrawnAsPartOfUkraine() {
        XCTAssertEqual(map.country(at: CGPoint(x: 1172, y: 213), tolerance: 1), "UA",
                       "the source draws Crimea as Russia; the generator moves it")
    }

    func testRussiaIsNotInEurope() {
        XCTAssertEqual(CountryCatalog.regionByCode["RU"]?.continent, .asia)
        XCTAssertFalse(CountryCatalog.codes(in: .europe).contains("RU"))
        XCTAssertTrue(CountryCatalog.codes(in: .northernAsia).contains("RU"))
    }

    func testEveryShapeOnTheMapCanBePickedFromTheList() {
        let unpickable = map.countries.keys.filter { !CountryCatalog.allCodes.contains($0) }
        XCTAssertTrue(unpickable.isEmpty,
                      "\(unpickable) are drawn but not offered, so they stay grey whatever is picked")
    }

    func testTheContinentsCoverEveryCountryExactlyOnce() {
        let covered = Continent.allCases.flatMap { CountryCatalog.codes(in: $0) }
        XCTAssertEqual(covered.count, CountryCatalog.allCodes.count)
        XCTAssertEqual(Set(covered), Set(CountryCatalog.allCodes))
    }

    func testTheRegionsCoverEveryCountryExactlyOnce() {
        let covered = CountryRegion.allCases.flatMap { CountryCatalog.codes(in: $0) }
        XCTAssertEqual(covered.count, CountryCatalog.allCodes.count)
        XCTAssertEqual(Set(covered), Set(CountryCatalog.allCodes))
    }

    func testEveryContinentHoldsTheRegionsThatNameIt() {
        for continent in Continent.allCases {
            let fromRegions = Set(continent.regions.flatMap { CountryCatalog.codes(in: $0) })
            XCTAssertEqual(fromRegions, Set(CountryCatalog.codes(in: continent)),
                           "\(continent) disagrees with its own regions")
            XCTAssertFalse(continent.regions.isEmpty)
        }
    }

    func testARegionRipplesOutWithinTheStaggerLimit() {
        let delays = MapTransition.staggered(Set(CountryCatalog.codes(in: .easternEurope)), in: map)
        XCTAssertTrue(delays.values.allSatisfy { $0 >= 0 && $0 <= MapTransition.maxStagger + 1e-9 })
        XCTAssertEqual(delays.values.max() ?? 0, MapTransition.maxStagger, accuracy: 1e-9)
    }
}
