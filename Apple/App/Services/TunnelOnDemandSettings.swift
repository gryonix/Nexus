import Combine
import Foundation
import VPNTunnel

@MainActor
final class TunnelOnDemandSettings: ObservableObject {
    static let shared = TunnelOnDemandSettings()

    @Published var isEnabled: Bool { didSet { save() } }
    @Published var scope: TunnelOnDemandPolicy.Scope { didSet { save() } }
    @Published var networkMode: TunnelOnDemandPolicy.NetworkMode { didSet { save() } }
    @Published private(set) var trustedNetworks: [String] { didSet { save() } }

    /// What gets applied
    var policy: TunnelOnDemandPolicy {
        TunnelOnDemandPolicy(isEnabled: isEnabled, scope: scope, networkMode: networkMode,
                             trustedNetworks: trustedNetworks)
    }

    private let defaults: UserDefaults
    private static let enabledKey = "tunnel.onDemand.enabled"
    private static let scopeKey = "tunnel.onDemand.scope"
    private static let trustedKey = "tunnel.onDemand.trustedNetworks"
    private static let modeKey = "tunnel.onDemand.networkMode"

    /// Called after any change, with the policy to apply
    var onChange: ((TunnelOnDemandPolicy) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.scope = Self.offeredHere(TunnelOnDemandPolicy.Scope(
            rawValue: defaults.string(forKey: Self.scopeKey) ?? "") ?? .anyNetwork)
        self.networkMode = TunnelOnDemandPolicy.NetworkMode(
            rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .exceptListed
        self.trustedNetworks = defaults.stringArray(forKey: Self.trustedKey) ?? []
    }

    /// The scope this device offers; a Mac has no cellular
    static func offeredHere(_ scope: TunnelOnDemandPolicy.Scope) -> TunnelOnDemandPolicy.Scope {
        #if os(macOS)
        return scope == .cellularOnly ? .anyNetwork : scope
        #else
        return scope
        #endif
    }

    /// Adds a network to the trusted list
    func trust(_ network: String) {
        let name = network.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !trustedNetworks.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        trustedNetworks.append(name)
    }

    func stopTrusting(_ network: String) {
        trustedNetworks.removeAll { $0 == network }
    }

    private func save() {
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(scope.rawValue, forKey: Self.scopeKey)
        defaults.set(networkMode.rawValue, forKey: Self.modeKey)
        defaults.set(trustedNetworks, forKey: Self.trustedKey)
        onChange?(policy)
    }
}
