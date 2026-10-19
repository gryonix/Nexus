import Foundation

public struct Mailbox: Sendable, Hashable, Identifiable {
    /// The address exactly as the server listed it
    public let address: String
    public let detail: String?

    public var id: String { address }

    public init(address: String, detail: String? = nil) {
        self.address = address
        self.detail = detail
    }

    public var localPart: String {
        String(address.split(separator: "@").first ?? "")
    }

    public var domain: String {
        address.split(separator: "@").count == 2
            ? String(address.split(separator: "@")[1])
            : ""
    }

    /// Whether the app may act on this mailbox at all
    public var isManageable: Bool {
        CommandCatalog.DockerMailserver.isValidAddress(address)
    }
}
