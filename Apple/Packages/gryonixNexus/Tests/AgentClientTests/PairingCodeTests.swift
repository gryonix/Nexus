import XCTest
@testable import AgentClient

final class PairingCodeTests: XCTestCase {
    func testParsesRealCLIBanner() {
        XCTAssertEqual(
            PairingCode.parse("Pairing code (valid 10 minutes): AKAD-M3RJ\n"),
            "AKAD-M3RJ")
    }

    /// A bare code on its own line (e.g
    func testParsesBareCode() {
        XCTAssertEqual(PairingCode.parse("AKAD-M3RJ"), "AKAD-M3RJ")
    }

    func testIgnoresLeadingLines() {
        let output = "starting up\nsome log line\nPairing code (valid 10 minutes): 7Q9M-KZ2P\n"
        XCTAssertEqual(PairingCode.parse(output), "7Q9M-KZ2P")
    }

    func testEmptyOutputIsNil() {
        XCTAssertNil(PairingCode.parse(""))
        XCTAssertNil(PairingCode.parse("\n   \n"))
    }
}
