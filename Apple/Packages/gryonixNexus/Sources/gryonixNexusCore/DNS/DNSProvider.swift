/// Applies DNS records at a specific DNS provider. The built-in flow exports
/// records as a paste-in artifact (dns-records.txt, rendered by the recipe's
/// DNS generator); API-backed implementations (e.g. Cloudflare) push the same
/// structured records automatically. Implementations are registered
/// separately — the core only defines the contract.
public protocol DNSProvider: Sendable {
    /// Human-readable provider name for UI/selection
    var displayName: String { get }
    /// Creates or updates the given records in the provider's zone
    func apply(_ records: [DNSRecord], zone: String) async throws
}

public struct DNSPublishOutcome: Sendable, Hashable {
    public enum Result: Sendable, Hashable {
        case created
        case updated
        case unchanged
        case failed(String)
    }

    public let record: DNSRecord
    public let result: Result

    public init(record: DNSRecord, result: Result) {
        self.record = record
        self.result = result
    }
}

public protocol DNSPublishingProvider: DNSProvider {
    /// Confirms the credential works before anything is written
    func verifyToken() async throws
    func publishReportingOutcomes(_ records: [DNSRecord], zone: String) async throws -> [DNSPublishOutcome]
    /// Removes these A records when they point at the address
    func removeAddressRecords(named names: [String], pointingAt address: String,
                              zone: String) async throws -> [String]
}

/// This provider cannot remove records from the app
public struct DNSRemovalUnsupported: Error {}

extension DNSPublishingProvider {
    public func removeAddressRecords(named names: [String], pointingAt address: String,
                                     zone: String) async throws -> [String] {
        throw DNSRemovalUnsupported()
    }
}
