import XCTest

@testable import gryonixNexus

final class CardAppearanceMenuTests: XCTestCase {
    private var listSource: String {
        get throws {
            let repoRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // AppTests
                .deletingLastPathComponent()   // Apple
            return try String(contentsOf: repoRoot
                .appendingPathComponent("App/Features/Servers/ServerListView.swift"),
                              encoding: .utf8)
        }
    }

    func testTheMenuIsBuiltFromButtons() throws {
        let menu = try appearanceChoicesBody()
        XCTAssertFalse(menu.contains("Picker("),
                       "the appearance menu is a Picker again — that is the control whose choice "
                       + "never reliably reached the card, and the size was then only changeable "
                       + "from Settings, which is the app-wide default and a different setting")
        XCTAssertTrue(menu.contains("menuChoice("),
                      "the appearance menu must be built from buttons that each carry their own tick")
    }

    func testMenuChoiceIsNotPlatformGated() throws {
        let source = try listSource
        guard let helper = source.range(of: "private func menuChoice(") else {
            XCTFail("menuChoice(_:picked:_:) is gone — the appearance menu has nothing left to "
                    + "build its buttons from")
            return
        }
        let before = source[..<helper.lowerBound]
        if let ifRange = before.range(of: "#if os(macOS)", options: .backwards),
           before.range(of: "#endif", options: .backwards, range: ifRange.upperBound..<before.endIndex) == nil {
            XCTFail("menuChoice is still wrapped in #if os(macOS) — iOS cannot reach it")
        }
    }

    func testTheMenuKeepsEveryChoice() throws {
        let menu = try appearanceChoicesBody()
        for question in ["Card size", "Load indicator", "Color"] {
            XCTAssertTrue(menu.contains("Section(\"\(question)\")"),
                          "the appearance menu no longer offers \(question)")
        }
        for answer in ["ServerCardSize.allCases", "ServerTint.allCases",
                       "Self.indicatorChoices"] {
            XCTAssertTrue(menu.contains(answer),
                          "the appearance menu stopped offering every \(answer)")
        }
        XCTAssertEqual(menu.components(separatedBy: "menuChoice(\"App default\"").count - 1, 2,
                       "the way back to the app-wide default is missing from the appearance menu")
        XCTAssertTrue(menu.contains("menuChoice(\"Default\""),
                      "the way back to the default colour is missing from the appearance menu")
    }

    func testEveryChoiceActsOnTheTargetedDeployment() throws {
        let menu = try appearanceChoicesBody()
        for setter in ["setCardSize(", "setIndicatorStyle(", "setTint("] {
            XCTAssertTrue(menu.contains(setter), "\(setter) call missing from the appearance menu")
        }
        XCTAssertFalse(menu.contains("cardColumns.cardSize ="),
                       "a choice in this menu wrote the app-wide default directly — that is the "
                       + "exact defect \"one card resizes the whole fleet\" came from")
        let setterCalls = menu.components(separatedBy: .newlines).filter {
            $0.contains("setCardSize(") || $0.contains("setIndicatorStyle(") || $0.contains("setTint(")
        }
        XCTAssertTrue(setterCalls.allSatisfy { $0.contains("for: target())") },
                      "a setter call in this menu does not close on `for: target())`: \(setterCalls)")
    }

    // MARK: - Slicing the source

    private func appearanceChoicesBody() throws -> String {
        let source = try listSource
        guard let start = source.range(of: "private func appearanceChoices("),
              let end = source.range(of: "private func menuChoice(", range: start.upperBound..<source.endIndex)
        else {
            XCTFail("`appearanceChoices` or the `menuChoice` helper right after it is gone or "
                    + "renamed — this test has to be pointed at whatever replaced them rather "
                    + "than left passing on an empty string")
            return ""
        }
        return String(source[start.upperBound..<end.lowerBound])
    }
}
