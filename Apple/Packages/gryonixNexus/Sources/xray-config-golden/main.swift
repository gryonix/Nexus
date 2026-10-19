import Foundation
import VPNProfile

let links: [String] = [
    // Shadowsocks, SIP002 with the credential base64-wrapped.
    "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#iPhone",
    "ss://2022-blake3-aes-256-gcm:uNFhgfrixCZZOfkYvKmSLQ==@vpn.example.com:8388#capture",
    // Reality with everything the panel sets, including the flow.
    "vless://3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f@vpn.example.com:443"
        + "?encryption=none&security=reality&sni=www.microsoft.com"
        + "&fp=chrome&pbk=xrK4Y_1n7Qk&sid=9a3f&type=tcp&flow=xtls-rprx-vision#iPhone",
    "vless://u@h.example.com:443?security=reality&pbk=k&sid=1",
    "vless://u@h.example.com:443?security=tls&type=ws&path=/vl&host=cdn.example.org&sni=a.b",
    // gRPC.
    "vless://u@h.example.com:443?security=tls&type=grpc&serviceName=gun",
    "vless://u@h.example.com:8080?encryption=none&security=none&flow=xtls-rprx-vision",
]

let access = LocalProxyAccess(port: 40123, username: "session-user", password: "session-pass")

var rows: [[String: Any]] = []
for link in links {
    let text = try XrayConfiguration.json(forLink: link, access: access)
    let document = try JSONSerialization.jsonObject(with: Data(text.utf8))
    rows.append(["link": link, "config": document])
}
let data = try JSONSerialization.data(withJSONObject: rows,
                                      options: [.sortedKeys, .prettyPrinted])
print(String(decoding: data, as: UTF8.self))
