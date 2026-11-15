import ServiceCatalog
import XCTest

@testable import VPNTunnel

final class ForeignTunnelConfigTests: XCTestCase {
    private let wireGuard = """
    [Interface]
    PrivateKey = cHJpdmF0ZWtleXByaXZhdGVrZXlwcml2YXRla2V5MTI=
    Address = 10.8.0.5/32
    DNS = 1.1.1.1

    [Peer]
    PublicKey = cHVibGlja2V5cHVibGlja2V5cHVibGlja2V5MTIzNA==
    AllowedIPs = 0.0.0.0/0
    Endpoint = vpn.example.net:51820
    """

    func testAWireGuardFileIsRecognised() throws {
        let detected = try ForeignTunnelConfig.detect("\n" + wireGuard + "\n")
        XCTAssertEqual(detected.protocolID, .wireguardVPN)
        XCTAssertEqual(detected.suggestedName, "vpn.example.net")
        XCTAssertTrue(detected.text.hasPrefix("[Interface]"))
    }

    func testObfuscationKeysMakeItAmneziaWG() throws {
        let amnezia = wireGuard.replacingOccurrences(of: "DNS = 1.1.1.1", with: "DNS = 1.1.1.1\nJc = 4\nJmin = 10\nJmax = 50")
        XCTAssertEqual(try ForeignTunnelConfig.detect(amnezia).protocolID, .amneziaWG)
    }

    func testAShadowsocksLinkKeepsItsName() throws {
        let link = "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpzZWNyZXQ@203.0.113.9:8388#Home%20VPN"
        let detected = try ForeignTunnelConfig.detect(link)
        XCTAssertEqual(detected.protocolID, .shadowsocks)
        XCTAssertEqual(detected.suggestedName, "Home VPN")
    }

    func testAVLESSLinkIsRecognised() throws {
        let link = "vless://00000000-0000-4000-8000-000000000001@vpn.example.net:443?security=reality&sni=example.org&fp=chrome&pbk=cHVibGlj&sid=ab&type=tcp&flow=xtls-rprx-vision"
        let detected = try ForeignTunnelConfig.detect(link)
        XCTAssertEqual(detected.protocolID, .xrayReality)
        XCTAssertEqual(detected.suggestedName, "vpn.example.net")
    }

    func testACompressedAmneziaKeyBecomesItsWireGuardText() throws {
        let detected = try ForeignTunnelConfig.detect("vpn://AAACoXicfVJtT8IwEP4rS-NHHHSDqEv4gIqARlzAIMKMqduhNV23dFUUwn_3rkDki6Zb9rxcb892XbO00FZIDaZikTdf_3KkTOQaVlIci-UrqyHFR-StmRKVfcbChSTO1gnbkgRZwuYDbcEsRApPSaI7WWagqry2xxv-qc_9oB4GqF8Ox6gdxaPBbWf0-Iy05h2Nuxd3w8sdx6LYyE9h4Qa-sTbtX5dZftWYPVgF0_NvMZ29Zb2JmU3VMs1V8DgdKRFMWrf3gzbuvU5xT5NALrV7vcPiC3GL8JgjChwKEIWE-qRxAiRRzn5IHoHmrh9e8xjA0NfFHy9Kpvt8E_nSU--U4S-M2VbDTpvydZQqlpANYvo3Dd-teqPmRVGdknR1VhZSW5cxRJPz0D-JWvzURY5xYLKyoO0NQCmU_ASqbFE-HFXC3orKDkUO25kctNjaZWEsWa7fhoZLCk3TKWyzeUItg4X4UPbinzORQZUaWVpZaHILQ4B0XXESzny3dlJAEm-eYZRgf5O1T0v2QVa2-QFUSckf")
        XCTAssertEqual(detected.protocolID, .amneziaWG)
        XCTAssertEqual(detected.suggestedName, "orion")
        XCTAssertTrue(detected.text.contains("DNS = 9.9.9.9, 149.112.112.112"))
        XCTAssertTrue(detected.text.contains("Endpoint = 203.0.113.7:51820"))
    }

    func testAnUncompressedAmneziaKeyIsReadToo() throws {
        XCTAssertEqual(try ForeignTunnelConfig.detect("vpn://eyJjb250YWluZXJzIjogW3siY29udGFpbmVyIjogImFtbmV6aWEtYXdnIiwgImF3ZyI6IHsibGFzdF9jb25maWciOiAie1wiY29uZmlnXCI6IFwiW0ludGVyZmFjZV1cXG5BZGRyZXNzID0gMTAuOC4xLjIvMzJcXG5ETlMgPSAkUFJJTUFSWV9ETlMsICRTRUNPTkRBUllfRE5TXFxuUHJpdmF0ZUtleSA9IGNISnBkbUYwWld0bGVYQnlhWFpoZEdWclpYbHdjbWwyWVhSbGEyVjVNVEk9XFxuSmMgPSA0XFxuSm1pbiA9IDEwXFxuSm1heCA9IDUwXFxuUzEgPSAyMFxcblMyID0gMzBcXG5IMSA9IDFcXG5IMiA9IDJcXG5IMyA9IDNcXG5INCA9IDRcXG5cXG5bUGVlcl1cXG5QdWJsaWNLZXkgPSBjSFZpYkdsamEyVjVjSFZpYkdsamEyVjVjSFZpYkdsamEyVjVNVEl6TkE9PVxcbkFsbG93ZWRJUHMgPSAwLjAuMC4wLzAsIDo6LzBcXG5FbmRwb2ludCA9IDIwMy4wLjExMy43OjUxODIwXFxuUGVyc2lzdGVudEtlZXBhbGl2ZSA9IDI1XFxuXCIsIFwiaG9zdE5hbWVcIjogXCIyMDMuMC4xMTMuN1wiLCBcInBvcnRcIjogNTE4MjB9IiwgInBvcnQiOiAiNTE4MjAifX1dLCAiZGVmYXVsdENvbnRhaW5lciI6ICJhbW5lemlhLWF3ZyIsICJkZXNjcmlwdGlvbiI6ICJvcmlvbiIsICJkbnMxIjogIjkuOS45LjkiLCAiZG5zMiI6ICIxNDkuMTEyLjExMi4xMTIiLCAiaG9zdE5hbWUiOiAiMjAzLjAuMTEzLjcifQ").suggestedName, "orion")
    }

    func testOpenVPNIsReadButNotCarried() {
        XCTAssertThrowsError(try ForeignTunnelConfig.detect("client\ndev tun\nremote vpn.example.net 1194\n")) {
            XCTAssertEqual($0 as? ForeignTunnelConfig.Failure, .notCarried(.openVPN))
        }
    }

    func testNoiseIsNotRecognised() {
        XCTAssertThrowsError(try ForeignTunnelConfig.detect("hello")) {
            XCTAssertEqual($0 as? ForeignTunnelConfig.Failure, .notRecognised)
        }
        XCTAssertThrowsError(try ForeignTunnelConfig.detect("  ")) {
            XCTAssertEqual($0 as? ForeignTunnelConfig.Failure, .empty)
        }
    }

    func testABrokenWireGuardFileIsUnreadable() {
        XCTAssertThrowsError(try ForeignTunnelConfig.detect("[Interface]\nAddress = 10.0.0.2/32\n")) {
            XCTAssertEqual($0 as? ForeignTunnelConfig.Failure, .unreadable)
        }
    }
}
