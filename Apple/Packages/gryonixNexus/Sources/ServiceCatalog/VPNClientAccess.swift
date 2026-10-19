import Foundation

/// Where a person gets a VPN client configuration from
public enum VPNClientAccess: String, Sendable, Hashable, Codable, CaseIterable {
    /// From the app only
    case app

    /// From the panel's own page only
    case panel

    case both

    /// Is the panel's web page published at `vpn.<domain>`?
    public var publishesPanelSite: Bool { self != .app }

    /// May the app manage devices for this deployment?
    public var allowsAppManagement: Bool { self != .panel }
}
