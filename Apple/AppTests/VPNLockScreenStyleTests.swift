import XCTest
@testable import gryonixNexus

final class VPNLockScreenStyleTests: XCTestCase {
    func testAStyleSavedWithoutTheCardKeepsItsIslandLook() throws {
        let saved = #"{"tint":"pink","compactDetail":"traffic","showsTimer":false,"#
            + #""showsProtocol":true,"showsServer":true,"showsTraffic":true}"#
        let style = try JSONDecoder().decode(VPNIslandStyle.self, from: Data(saved.utf8))
        XCTAssertEqual(style.tint, .pink)
        XCTAssertFalse(style.showsTimer)
        XCTAssertEqual(style.lockScreenStyle, .standard)
    }

    func testResettingTheIslandKeepsTheCard() {
        var style = VPNIslandStyle(tint: .orange)
        style.lockScreenStyle.showsTraffic = false
        let reset = style.islandReset
        XCTAssertEqual(reset.tint, VPNIslandStyle.standard.tint)
        XCTAssertFalse(reset.lockScreenStyle.showsTraffic)
    }

    func testAProtocolCarriesTheUsersOwnNameWhereSet() {
        var style = VPNIslandStyle()
        XCTAssertEqual(style.shortLabel(for: "VLESS / Reality"), "VLESS")
        XCTAssertEqual(style.fullLabel(for: "VLESS / Reality"), "VLESS / Reality")
        style.protocolLabels = ["VLESS": " VR ", "SS": "  "]
        XCTAssertEqual(style.shortLabel(for: "VLESS / Reality"), "VR")
        XCTAssertEqual(style.fullLabel(for: "VLESS / Reality"), "VR")
        XCTAssertEqual(style.shortLabel(for: "Shadowsocks"), "SS", "blank keeps the standard name")
        XCTAssertEqual(style.fullLabel(for: "WireGuard"), "WireGuard")
        style.protocolLabels = ["WG": "HOMETUNNEL"]
        XCTAssertEqual(style.shortLabel(for: "WireGuard"), "HOMETUNN", "cut to the island's room")
    }

    func testAStyleSavedBeforeOwnNamesStillReads() throws {
        let saved = #"{"tint":"blue","compactDetail":"protocolName","showsTimer":true,"#
            + #""showsProtocol":true,"showsServer":true,"showsTraffic":false}"#
        let style = try JSONDecoder().decode(VPNIslandStyle.self, from: Data(saved.utf8))
        XCTAssertNil(style.protocolLabels)
        XCTAssertEqual(style.shortLabel(for: "AmneziaWG"), "AWG")
    }
}
