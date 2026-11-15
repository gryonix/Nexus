import Foundation
import gryonixNexusCore
import MailRecipe
import ServerControl
import ServiceCatalog

enum HomeOnlyDNS {
    enum Action { case remove, restore }

    /// Records to change by hand
    struct Manual: Equatable {
        let action: Action
        let records: [DNSRecord]

        var lines: [String] { records.map { "\($0.name) \($0.type.rawValue) \($0.value)" } }
    }

    enum Outcome: Equatable {
        case done([String])
        case failed([String])
        case manual(Manual)
    }

    static func records(for service: any ManagedService, in deployment: Deployment,
                        lookup: (String) async -> [String] = ServiceDNSPublisher.resolvedIPv4) async -> [DNSRecord] {
        let names = ServiceDNSPublisher.hostnames(of: service, in: deployment)
        guard let address = await ServiceDNSPublisher.address(of: deployment, lookup: lookup)
                ?? deployment.entry.host.nilIfEmpty else { return [] }
        return names.map { DNSRecord(name: $0, type: .a, value: address) }
    }

    @MainActor
    static func change(_ action: Action, _ service: any ManagedService, in deployment: Deployment,
                       provider: () async -> (any DNSPublishingProvider)? = savedProvider,
                       lookup: (String) async -> [String] = ServiceDNSPublisher.resolvedIPv4) async -> Outcome {
        let records = await records(for: service, in: deployment, lookup: lookup)
        let byHand = Outcome.manual(Manual(action: action, records: records))
        guard !records.isEmpty, deployment.scope.publishesAddressRecords,
              !deployment.services.contains(.cloudflared), let provider = await provider() else { return byHand }
        let zones = [deployment.domain] + deployment.additionalDomains
        var lines: [String] = []
        var failed = false
        for zone in zones {
            let owned = records.filter { DNSRecordGenerator.zone(of: $0, among: zones) == zone }
            guard !owned.isEmpty else { continue }
            do {
                lines += try await apply(action, owned, zone: zone, provider: provider)
            } catch is DNSRemovalUnsupported {
                return byHand
            } catch {
                failed = true
                lines.append("\(zone): \(error.localizedDescription)")
            }
        }
        return failed ? .failed(lines) : .done(lines)
    }

    private static func apply(_ action: Action, _ records: [DNSRecord], zone: String,
                              provider: any DNSPublishingProvider) async throws -> [String] {
        switch action {
        case .remove:
            let removed = try await provider.removeAddressRecords(
                named: records.map(\.name), pointingAt: records[0].value, zone: zone)
            return [UIL10n.string("%@: removed %lld DNS record(s).", zone, removed.count)]
        case .restore:
            let outcomes = try await provider.publishReportingOutcomes(records, zone: zone)
            let failures = outcomes.filter { if case .failed = $0.result { return true } else { return false } }
            if failures.isEmpty { return [UIL10n.string("%@: DNS records are in place.", zone)] }
            throw DNSRestoreFailure(count: failures.count)
        }
    }

    struct DNSRestoreFailure: LocalizedError {
        let count: Int
        var errorDescription: String? { UIL10n.string("%lld DNS record(s) could not be published.", count) }
    }

    @MainActor
    static func savedProvider() async -> (any DNSPublishingProvider)? {
        guard let credential = DNSCredentials.shared.selected ?? DNSCredentials.shared.all.first,
              let token = await DNSCredentialTokenStore.load(credential), !token.isEmpty else { return nil }
        return credential.kind.makeProvider(token: token)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
