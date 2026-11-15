import XCTest
@testable import ServerControl

final class SystemdShowParserTests: XCTestCase {
    func testTheStatusParserKeepsLoadedUnitsOnly() {
        let output = """
        Id=odio-api.service
        LoadState=loaded
        ActiveState=active

        Id=mympd.service
        LoadState=not-found
        ActiveState=inactive

        Id=mpd.service
        LoadState=loaded
        ActiveState=failed
        """
        let rows = SystemdShowParser.parse(output)
        XCTAssertEqual(rows.map(\.name), ["odio-api.service", "mpd.service"])
        XCTAssertEqual(rows.map(\.health), [.ok, .critical])
    }
}
