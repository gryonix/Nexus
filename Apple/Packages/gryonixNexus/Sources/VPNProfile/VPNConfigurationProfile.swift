import CryptoKit
import Foundation
import ServiceCatalog

public enum VPNConfigurationProfile {
    public enum Platform: Sendable {
        case iOS, macOS

        public static var current: Platform {
            #if os(macOS)
            return .macOS
            #else
            return .iOS
            #endif
        }
    }

    public static func handlerBundleID(for protocolID: ServiceID, on platform: Platform) -> String? {
        switch (protocolID, platform) {
        case (.wireguardVPN, .iOS): return "com.wireguard.ios"
        case (.wireguardVPN, .macOS): return "com.wireguard.macos"
        case (.amneziaWG, .iOS): return "org.amnezia.awg"
        case (.openVPN, .iOS): return "net.openvpn.connect.app"
        default: return nil
        }
    }

    public static func isSupported(_ protocolID: ServiceID, on platform: Platform) -> Bool {
        handlerBundleID(for: protocolID, on: platform) != nil
    }

    public enum ProfileError: LocalizedError, Equatable {
        case unsupportedProtocol(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedProtocol(let name):
                return "\(name) cannot be added to this device as a VPN configuration."
            }
        }
    }

    /// The profile for one WireGuard or AmneziaWG device
    public static func plist(for config: WireGuardQuickConfig,
                             protocolID: ServiceID,
                             deviceName: String,
                             identifier: String,
                             platform: Platform) throws -> Data {
        try plist(vendorConfig: ["WgQuickConfig": config.rawText],
                  remoteAddress: config.endpoint,
                  protocolID: protocolID,
                  deviceName: deviceName,
                  identifier: identifier,
                  platform: platform)
    }

    /// The profile for one OpenVPN device
    public static func plist(for config: OpenVPNProfileConfig,
                             deviceName: String,
                             identifier: String,
                             platform: Platform) throws -> Data {
        try plist(vendorConfig: config.vendorConfig,
                  remoteAddress: "DEFAULT",
                  protocolID: .openVPN,
                  deviceName: deviceName,
                  identifier: identifier,
                  platform: platform)
    }

    /// The payload every protocol shares
    private static func plist(vendorConfig: [String: String],
                              remoteAddress: String,
                              protocolID: ServiceID,
                              deviceName: String,
                              identifier: String,
                              platform: Platform) throws -> Data {
        guard let handler = handlerBundleID(for: protocolID, on: platform) else {
            throw ProfileError.unsupportedProtocol(protocolID.displayName)
        }

        let rootID = "com.skaymer.gryonixnexus.\(identifier)"
        let payloadID = "\(rootID).tunnel"
        let payload: [String: Any] = [
            "PayloadType": "com.apple.vpn.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": payloadID,
            "PayloadUUID": uuid(from: payloadID),
            "PayloadDisplayName": "VPN",
            "UserDefinedName": deviceName,
            "VPNType": "VPN",
            "VPNSubType": handler,
            "VendorConfig": vendorConfig,
            "VPN": [
                "RemoteAddress": remoteAddress,
                "AuthenticationMethod": "Password"
            ]
        ]

        let root: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": rootID,
            "PayloadUUID": uuid(from: rootID),
            "PayloadDisplayName": "\(protocolID.displayName) · \(deviceName)",
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [payload]
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    static func uuid(from identifier: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(identifier.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { range -> String in
            String(Array(hex)[range])
        }
        return groups.joined(separator: "-")
    }
}
