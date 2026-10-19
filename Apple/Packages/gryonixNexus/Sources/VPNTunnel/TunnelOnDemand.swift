import Foundation

public struct TunnelOnDemandPolicy: Codable, Equatable, Sendable {
    /// What the tunnel comes up for
    public enum Scope: String, Codable, Sendable, CaseIterable {
        /// Any network at all, cellular included
        case anyNetwork
        /// Wi-Fi only
        case wiFiOnly
        /// Cellular only
        case cellularOnly
    }

    /// How the listed Wi-Fi networks are read
    public enum NetworkMode: String, Codable, Sendable, CaseIterable {
        /// The tunnel stays down on the listed networks
        case exceptListed
        /// The tunnel comes up only on the listed networks
        case onlyListed
    }

    public var isEnabled: Bool
    public var scope: Scope
    public var networkMode: NetworkMode
    /// Wi-Fi networks the mode applies to, by name
    public var trustedNetworks: [String]

    public static let off = TunnelOnDemandPolicy(isEnabled: false,
                                                 scope: .anyNetwork,
                                                 trustedNetworks: [])

    public init(isEnabled: Bool, scope: Scope, networkMode: NetworkMode = .exceptListed,
                trustedNetworks: [String]) {
        self.isEnabled = isEnabled
        self.scope = scope
        self.networkMode = networkMode
        self.trustedNetworks = trustedNetworks
    }

    public enum Rule: Equatable, Sendable {
        /// Down on these Wi-Fi networks; every Wi-Fi when empty
        case disconnectOnWiFi(networks: [String])
        /// Up on these Wi-Fi networks; every Wi-Fi when empty
        case connectOnWiFi(networks: [String])
        case connectOnCellular
        case disconnectOnCellular
        case connectOnAnything
    }

    /// The rules, in the order the system evaluates them
    public var rules: [Rule] {
        guard isEnabled else { return [] }
        let listed = trustedNetworks.filter { !$0.isEmpty }
        return wiFiRules(listed) + cellularRules
    }

    private func wiFiRules(_ listed: [String]) -> [Rule] {
        guard scope != .cellularOnly else { return [.disconnectOnWiFi(networks: [])] }
        switch (networkMode, listed.isEmpty) {
        case (_, true):
            return [.connectOnWiFi(networks: [])]
        case (.exceptListed, false):
            return [.disconnectOnWiFi(networks: listed), .connectOnWiFi(networks: [])]
        case (.onlyListed, false):
            return [.connectOnWiFi(networks: listed), .disconnectOnWiFi(networks: [])]
        }
    }

    private var cellularRules: [Rule] {
        switch scope {
        case .anyNetwork: [.connectOnCellular, .connectOnAnything]
        case .wiFiOnly: [.disconnectOnCellular]
        case .cellularOnly: [.connectOnCellular]
        }
    }
}
