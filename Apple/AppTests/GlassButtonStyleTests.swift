import XCTest

@testable import gryonixNexus

final class GlassButtonStyleTests: XCTestCase {
    /// Styles that are a DECISION about how a button looks
    private let decided = [".buttonStyle(.glass)",
                           ".buttonStyle(.glassProminent)",
                           ".buttonStyle(.bordered)",
                           ".buttonStyle(.borderedProminent)"]

    private let helperFile = "LiquidGlass.swift"

    private var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("App")
    }

    func testNoScreenPicksAGlassOrBorderedStyleOfItsOwn() throws {
        let files = try swiftFiles(in: appSources)
        XCTAssertGreaterThan(files.count, 50, "the source sweep found almost nothing — check the path")

        var offenders: [String] = []
        for file in files where file.lastPathComponent != helperFile {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Prose about the rule is not a use of it.
                if trimmed.hasPrefix("//") { continue }
                for style in decided where line.contains(style) {
                    offenders.append("\(file.lastPathComponent):\(index + 1)  \(trimmed)")
                }
            }
        }

        XCTAssertEqual(offenders, [], """
            These buttons choose their own style, so they will read differently \
            on the Mac and on older systems from every other button in the app. \
            Use the helpers in \(helperFile) — prominentActionButtonStyle, \
            secondaryActionButtonStyle, rowActionButtonStyle, \
            glassIconButtonStyle, glassTileButtonStyle:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The other half: the helpers are actually USED
    func testTheHelpersAreTheOnesInUse() throws {
        let files = try swiftFiles(in: appSources)
        var counts: [String: Int] = [:]
        for file in files where file.lastPathComponent != helperFile {
            let source = try String(contentsOf: file, encoding: .utf8)
            for helper in ["prominentActionButtonStyle()", "secondaryActionButtonStyle()",
                           "rowActionButtonStyle(", "glassIconButtonStyle()",
                           "glassTileButtonStyle()"] {
                counts[helper, default: 0] += source.components(separatedBy: helper).count - 1
            }
        }
        for (helper, count) in counts {
            XCTAssertGreaterThan(count, 0, "\(helper) is declared and called nowhere — a dead seam")
        }
        XCTAssertGreaterThanOrEqual(counts["rowActionButtonStyle(", default: 0], 20,
                                    "far fewer row actions than the sweep left behind")
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
