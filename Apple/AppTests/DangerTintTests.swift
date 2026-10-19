import XCTest

@testable import gryonixNexus

/// Every destructive button in the app is painted red explicitly
final class DangerTintTests: XCTestCase {
    /// `App/` as it sits on disk
    private var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("App")
    }

    func testEveryDestructiveButtonCarriesAnExplicitRedTint() throws {
        let files = try swiftFiles(in: appSources)
        XCTAssertGreaterThan(files.count, 50, "the source sweep found almost nothing — check the path")

        var offenders: [String] = []
        var checked = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("role: .destructive") else { continue }
            let lines = source.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("role: .destructive") {
                // Prose about the rule is not a use of it.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let back = lines[max(0, index - 6)...index].joined(separator: "\n")
                if back.contains("CompactAction(") || back.contains("CompactActionButton(") { continue }
                checked += 1
                var window = lines[index..<min(index + 14, lines.count)].joined(separator: "\n")
                let ownDeclaration = (window.range(of: "Button(")?.upperBound) ?? window.startIndex
                if let next = window.range(of: "Button(", range: ownDeclaration..<window.endIndex) {
                    window = String(window[window.startIndex..<next.lowerBound])
                }
                let painted = window.contains(".dangerTint()")
                    || window.contains(".tint(.red)")
                    || window.contains(".foregroundStyle(.red)")
                if !painted {
                    offenders.append("\(file.lastPathComponent):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertGreaterThan(checked, 35, "far fewer destructive buttons than this app has — the sweep is not reading the sources")
        XCTAssertEqual(offenders, [], """
            These destructive buttons take their colour from the accent, so on a \
            green accent they are drawn in the same green as the action beside \
            them. Add .dangerTint():
            \(offenders.joined(separator: "\n"))
            """)
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
