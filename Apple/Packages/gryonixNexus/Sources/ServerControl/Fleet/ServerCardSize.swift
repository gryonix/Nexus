import Foundation

/// How big one server's card is drawn in the list
public enum ServerCardSize: String, Codable, Sendable, CaseIterable, Identifiable {
    case wide
    /// Half width, so two can share a row
    case compact

    public var id: String { rawValue }
}
