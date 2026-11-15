import Foundation
import gryonixNexusCore
import TVLink

/// How long a paired phone's word unlocks an Apple TV
enum TVLicenceRule {
    static let grace: TimeInterval = 10 * 24 * 3600
    static let lifetimeGrace: TimeInterval = 20 * 24 * 3600

    static func unlock(_ phone: TVPairedPhone,
                       publicKey: String = LicenseToken.productionKey) -> (plan: LicenseToken.Plan, until: Date)? {
        guard let vouch = phone.licence, vouch.active, let said = phone.licenceAt else { return nil }
        let plan = vouch.plan.flatMap(LicenseToken.Plan.init(rawValue:)) ?? .monthly
        var end = said.addingTimeInterval(plan == .lifetime ? lifetimeGrace : grace)
        if let expires = vouch.expires {
            end = min(end, Date(timeIntervalSince1970: TimeInterval(expires)))
        }
        if let token = vouch.token {
            guard let device = vouch.device,
                  let checked = try? LicenseToken.verify(token, device: device, now: said, publicKey: publicKey)
            else { return nil }
            if let expires = checked.expires { end = min(end, expires) }
        }
        return (plan, end)
    }

    /// The best unlock among the paired phones still in force
    static func best(_ phones: [TVPairedPhone], now: Date = Date(),
                     publicKey: String = LicenseToken.productionKey) -> (plan: LicenseToken.Plan, until: Date)? {
        phones.compactMap { unlock($0, publicKey: publicKey) }
            .filter { $0.until > now }
            .max { $0.until < $1.until }
    }
}
