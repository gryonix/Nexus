import Foundation
import VPNProfile

let cases: [(ProxyLinkConfig.Kind, String)] = [
    // The ordinary shapes, both protocols.
    (.shadowsocks, "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#iPhone\n"),
    (.vless, "vless://3f1c-uuid@vpn.example.com:443?encryption=none&security=reality"
        + "&sni=www.microsoft.com&fp=chrome&pbk=xrK4Y_1n7Qk&sid=9a3f&flow=xtls-rprx-vision#iPhone"),
    (.shadowsocks, "ss://YWVzLTI1Ni1nY206c2VjcmV0QHZwbi5leGFtcGxlLmNvbTo4Mzg4#iPhone"),
    // A password with colons in it. The FIRST colon separates.
    (.shadowsocks, "ss://" + Data("chacha20-ietf-poly1305:a:b:c@h.example.com:443".utf8)
        .base64EncodedString()),
    (.shadowsocks, "ss://YWVzLTI1Ni1nY206c2Vjcg@h.example.com:8388#p"),
    // The credential in the clear, which SIP002 also permits.
    (.shadowsocks, "ss://aes-256-gcm:secret@h.example.com:8388#p"),
    (.shadowsocks, "ss://YWVzLTI1Ni1nY206c2VjcmV0@h.example.com:8388#iPhone Марины"),
    (.vless, "vless://u@h.example.com:443#Мой телефон"),
    (.shadowsocks, "# gryonixVPN\n\nss://YWVzLTI1Ni1nY206c2VjcmV0@h.example.com:8388#p\n"),
    (.vless, "vless://u@h.example.com:8080?encryption=none&security=none"),
    // `peer` as the older spelling of `sni`.
    (.vless, "vless://u@h.example.com:443?security=tls&peer=example.org"),
    (.vless, "vless://u@h.example.com#p"),
    (.vless, "vless://u@h.example.com:70000#p"),
    (.shadowsocks, "ss://h.example.com:8388"),
    (.shadowsocks, "this is not a link"),
    (.vless, "ss://YWVzOnB3@h.example.com:8388#p"),
    (.vless, "vless://u@h.example.com:443?security=tls&type=ws&path=/vl&host=cdn.example.org"),
    (.vless, "vless://u@h.example.com:443?security=tls&type=grpc&serviceName=gun"),
    (.vless, "vless://u@h.example.com:443?security=tls&type=quic"),
    (.vless, "vless://u@h.example.com:443?security=xtls"),
    (.vless, "vless://u@h.example.com:443?security=none&flow=xtls-rprx-vision"),
    // A plugin the datapath cannot run: refused, never dropped silently.
    (.shadowsocks, "ss://YWVzLTI1Ni1nY206c2VjcmV0@h.example.com:8388?plugin=v2ray-plugin%3Btls#p"),
]

for (kind, text) in cases {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
    let answer: String
    do {
        let link = try ProxyLinkConfig(parsing: text, kind: kind)
        let credential: String
        switch link.credential {
        case .shadowsocks(let method, let password):
            credential = ["shadowsocks", method, password].joined(separator: "\t")
        case .vless(let vless):
            credential = ["vless", vless.uuid, vless.security, vless.sni, vless.fingerprint,
                          vless.publicKey, vless.shortID, vless.flow,
                          vless.network, vless.path, vless.host, vless.serviceName]
                .joined(separator: "\t")
        }
        answer = "ok\t\(link.endpoint)\t\(link.label)\t\(credential)"
    } catch let failure as ProxyLinkConfig.ParseError {
        switch failure {
        case .noLink: answer = "fail\tnoLink"
        case .noEndpoint: answer = "fail\tnoEndpoint"
        case .noCredential: answer = "fail\tnoCredential"
        case .unsupportedTransport(let name): answer = "fail\tunsupportedTransport\t\(name)"
        }
    } catch {
        answer = "fail\tunknown"
    }
    print("\(kind.rawValue)\t\(escaped)\t\(answer)")
}
