import Foundation
import ServiceCatalog
import VPNProfile

let cases: [(ServiceID, String, VPNConfigurationProfile.Platform)] = [
    // The ordinary shapes, both protocols.
    (.shadowsocks, "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#phone\n", .iOS),
    (.xrayReality, "vless://5f1c-uuid@vpn.example.com:8443?encryption=none&security=reality#phone\n", .iOS),
    (.shadowsocks, "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#phone\n", .macOS),
    (.shadowsocks, "ss://YWVzOnB3@vpn.example.com:8388#iPhone Марины", .iOS),
    (.xrayReality, "vless://u@h:443#Мой телефон", .iOS),
    (.shadowsocks, "ss://YWVzOnB3@vpn.example.com:8388#a+b&c=d", .iOS),
    // No link in the text at all.
    (.shadowsocks, "this is not a link", .iOS),
    (.shadowsocks, "", .iOS),
    (.xrayReality, "   ", .iOS),
    // Right shape, wrong protocol.
    (.xrayReality, "ss://YWVzOnB3@vpn.example.com:8388#p", .iOS),
    (.shadowsocks, "vless://u@h:443#p", .iOS),
    // The line found among others, and with leading whitespace.
    (.shadowsocks, "# exported by the panel\n\nss://YWVzOnB3@h:8388#p\n", .iOS),
    (.shadowsocks, "note\n   ss://YWVzOnB3@h:8388#p\nmore\n", .iOS),
    // Two links: the FIRST one wins.
    (.shadowsocks, "ss://one@h:1#a\nss://two@h:2#b\n", .iOS),
    // A scheme that only looks right.
    (.shadowsocks, "sss://YWVzOnB3@h:8388#p", .iOS),
    (.shadowsocks, "ss:/YWVzOnB3@h:8388#p", .iOS),
    // No fragment at all, and an empty one.
    (.shadowsocks, "ss://YWVzOnB3@h:8388", .iOS),
    (.shadowsocks, "ss://YWVzOnB3@h:8388#", .iOS),
    (.shadowsocks, "ss://YWVzOnB3@h:8388# !\"$%&'()*+,-./0:;<=>?@AZ[\\]^_`az{|}~", .iOS)
]

for (id, text, platform) in cases {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
    let answer: String
    switch VPNConfigurationHandoff.route(protocolID: id, text: text, platform: platform) {
    case .openIn(let url): answer = "openIn\t\(url.absoluteString)"
    case .fileOnly: answer = "fileOnly"
    case .configurationProfile: answer = "configurationProfile"
    }
    print("\(id.rawValue)\t\(escaped)\t\(answer)")
}
