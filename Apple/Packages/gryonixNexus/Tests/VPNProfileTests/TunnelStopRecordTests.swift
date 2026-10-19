import XCTest
@testable import VPNProfile

final class TunnelStopRecordTests: XCTestCase {
    func testAStopHandlerLeavesItsReasonAndAStartClearsIt() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let record = TunnelStopRecord(url: url)
        XCTAssertNil(record.read(), "no file means the stop handler never ran")
        record.write(reason: 1)
        XCTAssertEqual(record.read(), 1)
        record.clear()
        XCTAssertNil(record.read())
    }

    func testTheTunnelsNotesAndTheSystemReasonAreShownTogether() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let record = TunnelStopRecord(url: folder.appendingPathComponent(TunnelStopRecord.fileName))
        XCTAssertNil(record.explanation())
        record.note("The packet stack stopped.")
        record.write(reason: 2)
        XCTAssertEqual(record.explanation(), "The packet stack stopped.\nStop reason: providerFailed (2)")
        record.clear()
        XCTAssertNil(record.explanation())
        XCTAssertEqual(TunnelStopRecord.reasonName(99), "unknown")
    }

    func testATunnelThatVanishedShowsWhenItWasLastAlive() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let record = TunnelStopRecord(url: folder.appendingPathComponent(TunnelStopRecord.fileName))
        record.heartbeat("16:47:55, memory 48.2 MB")
        XCTAssertEqual(record.explanation(), "Ended abruptly; last alive 16:47:55, memory 48.2 MB")
        record.write(reason: 1)
        XCTAssertEqual(record.explanation(), "Stop reason: userInitiated (1)")
    }

    func testAGoPanicIsShownWithItsFirstFrames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let record = TunnelStopRecord(url: folder.appendingPathComponent(TunnelStopRecord.fileName))
        let trace = (["panic: runtime error: index out of range", "", "goroutine 7 [running]:"]
            + (1...20).map { "frame \($0)" }).joined(separator: "\n")
        try Data(trace.utf8).write(to: XCTUnwrap(record.crashURL))
        let shown = try XCTUnwrap(record.explanation()).split(separator: "\n")
        XCTAssertEqual(shown.first, "panic: runtime error: index out of range")
        XCTAssertEqual(shown.count, 12, "blank lines dropped, twelve lines kept")
        record.clear()
        XCTAssertNil(record.explanation())
    }
}
