import CryptoKit
import Foundation
import ServiceCatalog

extension Deployment {
    public var hostsRefusingVPN: [String] {
        let context = serviceContext
        let hosts = ServiceRegistry.all
            .filter { homeOnlyServices.contains($0.id) && homeOnlyNoVPN.contains($0.id) }
            .compactMap { $0.webIngress(context)?.hostname }
            .flatMap { [$0] + context.mirroredHostnames(of: $0) }
        return Array(Set(hosts)).sorted()
    }

    /// Whether the service's address records are taken down
    public func hasDNSRecordRemoved(_ id: ServiceID) -> Bool { homeOnlyDNSRemoved.contains(id) }
}

/// Which relay ports a closed-service check asks about
public enum PublicPortProbe {
    /// The service's own TCP ports, never the shared web ports
    public static func ports(of service: any ManagedService, in deployment: Deployment) -> [Int] {
        ForwardedPorts.ownTCP(of: service, context: deployment.serviceContext)
    }

    public enum Verdict: Equatable, Sendable {
        case closed
        case open([Int])
    }

    public static func verdict(asked: [Int], open: [Int]) -> Verdict {
        let leaks = asked.filter(open.contains).sorted()
        return leaks.isEmpty ? .closed : .open(leaks)
    }
}

public enum InternalCertificateProfile {
    public static func der(fromPEM pem: String) -> Data? {
        let body = pem.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: body), !data.isEmpty else { return nil }
        return data
    }

    public static func mobileconfig(pem: String, serverName: String) -> Data? {
        guard let certificate = der(fromPEM: pem) else { return nil }
        let digest = SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
        let suffix = String(digest.prefix(12))
        let payload: [String: Any] = [
            "PayloadType": "com.apple.security.root",
            "PayloadVersion": 1,
            "PayloadIdentifier": "app.gryonixnexus.rootca.\(suffix).cert",
            "PayloadUUID": uuid(from: digest, salt: "cert"),
            "PayloadDisplayName": "\(serverName) certificate",
            "PayloadContent": certificate,
        ]
        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "app.gryonixnexus.rootca.\(suffix)",
            "PayloadUUID": uuid(from: digest, salt: "profile"),
            "PayloadDisplayName": "\(serverName) certificate",
            "PayloadContent": [payload],
        ]
        return try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    private static func uuid(from digest: String, salt: String) -> String {
        let hash = SHA256.hash(data: Data((digest + salt).utf8)).map { String(format: "%02X", $0) }.joined()
        let h = Array(hash)
        let parts = [h[0..<8], h[8..<12], h[12..<16], h[16..<20], h[20..<32]].map { String($0) }
        return parts.joined(separator: "-")
    }
}
