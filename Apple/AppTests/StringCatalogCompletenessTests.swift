import XCTest
@testable import gryonixNexus

final class StringCatalogCompletenessTests: XCTestCase {
    /// The eight the base language is translated INTO
    private static let languages = ["de", "es", "fr", "it", "ja", "ru", "uk", "zh"]

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let value: String? }
                let stringUnit: Unit?
                /// Plurals and device variants carry their text one level deeper
                let variations: Variations?
                struct Variations: Decodable {
                    init(from decoder: Decoder) throws { _ = decoder }
                }
            }
            let localizations: [String: Localization]?
            let shouldTranslate: Bool?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func catalog() throws -> Catalog {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Localizable-catalog",
                                                            withExtension: "json"),
                                "the catalog is not bundled with these tests — see project.yml")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    /// The guard itself
    func testEveryKeyIsTranslatedIntoEveryLanguage() throws {
        var gaps: [String] = []
        for (key, entry) in try catalog().strings {
            if entry.shouldTranslate == false { continue }
            let localizations = entry.localizations ?? [:]
            let missing = Self.languages.filter { language in
                guard let localization = localizations[language] else { return true }
                if let value = localization.stringUnit?.value, !value.isEmpty { return false }
                return localization.variations == nil
            }
            if !missing.isEmpty {
                gaps.append("\(key.prefix(60)) — missing \(missing.joined(separator: ", "))")
            }
        }
        XCTAssertEqual(gaps.sorted(), [],
                       "These strings ship in English on the languages listed. Add them with a Tools/add-*-strings.py script — the catalog is edited pointwise and never re-sorted (GOTCHAS).")
    }

    func testTheCatalogIsTheRealOne() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog.sourceLanguage, "en")
        XCTAssertGreaterThan(catalog.strings.count, 1000,
                             "a catalog this small is not the app's — the check above would be green on nothing")
        XCTAssertNotNil(catalog.strings["Use on this device"],
                        "the catalog does not carry a key this slice certainly added")
    }

    func testTheUntranslatedListStaysSmall() throws {
        let exempt = try catalog().strings.filter { $0.value.shouldTranslate == false }
        XCTAssertLessThan(exempt.count, 40,
                          "\(exempt.count) keys are marked untranslatable: \(exempt.keys.sorted().prefix(20))")
    }
}
