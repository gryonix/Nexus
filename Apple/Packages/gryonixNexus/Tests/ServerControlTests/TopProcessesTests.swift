import Foundation
@testable import ServerControl
import XCTest

final class TopProcessesTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Android/servercontrol/src/test/resources/processes")
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    func testRealTopOutputReadsTheSecondSampleWithoutItself() throws {
        let text = String(decoding: try fixture("top-orion.txt"), as: UTF8.self)
        let samples = TopProcesses.parse(text)
        XCTAssertGreaterThan(samples.count, 150)
        XCTAssertFalse(samples.contains { $0.command.hasPrefix("top -b") })
        let hass = try XCTUnwrap(samples.first { $0.command.contains("homeassistant") })
        XCTAssertEqual(hass.cpu, 1.0)
        XCTAssertEqual(hass.memoryKiB, 216_960)
        XCTAssertEqual(samples.first?.command.hasPrefix("/usr/bin/dbus-daemon"), true)
    }

    func testFriendlyRowsGroupAndSortByMemory() throws {
        let text = String(decoding: try fixture("top-orion.txt"), as: UTF8.self)
        let rows = TopProcesses.rows(TopProcesses.parse(text), friendly: true, byMemory: true)
        XCTAssertEqual(rows.first?.name, "Home Assistant")
        let all = TopProcesses.rows(TopProcesses.parse(text), friendly: true, byMemory: true, limit: .max)
        let kernel = try XCTUnwrap(all.first { $0.name == "Linux" })
        XCTAssertGreaterThan(kernel.count, 50, "kernel threads fold into one row")
        XCTAssertEqual(all.filter { $0.name == "Linux" }.count, 1)
        let system = TopProcesses.rows(TopProcesses.parse(text), friendly: false, byMemory: true)
        XCTAssertEqual(system.first?.name, "python3")
        XCTAssertEqual(system.first?.detail, "python3 -P -m homeassistant --config /config")
    }

    func testNamesMatchTheSharedTable() throws {
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("process-names.json")) as? [[Any]])
        for pair in cases {
            let command = try XCTUnwrap(pair[0] as? String)
            XCTAssertEqual(ProcessNames.friendly(command), pair[1] as? String, command)
        }
    }
}
