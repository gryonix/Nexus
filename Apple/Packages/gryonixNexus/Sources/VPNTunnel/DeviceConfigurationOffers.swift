import Foundation
import ServiceCatalog
import VPNProfile

public enum DeviceConfigurationOffers {
    public struct Offers: Equatable, Sendable {
        /// This app can carry the tunnel itself
        public let keepsHere: Bool
        /// What can be handed to somebody else, if anything
        public let handoff: ConfigurationHandoff

        public var isEmpty: Bool { !keepsHere && handoff == .fileOnly }
    }

    public static func offers(protocolID: ServiceID,
                              text: String,
                              platform: VPNConfigurationProfile.Platform) -> Offers {
        Offers(keepsHere: TunnelProfileBuilder.canCarry(text: text, protocolID: protocolID),
               handoff: VPNConfigurationHandoff.route(protocolID: protocolID,
                                                      text: text,
                                                      platform: platform))
    }

    /// What the `.mobileconfig` written for the system is called
    public static func profileFileName(from panelFileName: String,
                                       deviceName: String) -> String {
        let parts = panelFileName.split(separator: ".", omittingEmptySubsequences: false)
        let stem = parts.count > 1 ? parts.dropLast().joined(separator: ".") : panelFileName
        let trimmed = stem.trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty ? deviceName : trimmed) + ".mobileconfig"
    }
}
