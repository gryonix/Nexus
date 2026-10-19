import Foundation
import gryonixNexusCore
import MailRecipe
import ServerControl
import ServiceCatalog

/// Address records for a service added after setup
enum ServiceDNSPublisher {
    /// Every name the service answers on, mirrored domains included
    static func hostnames(of service: any ManagedService, in deployment: Deployment) -> [String] {
        let context = deployment.serviceContext
        var names: [String] = []
        if let ingress = service.webIngress(context) {
            names += context.servedHostnames(of: ingress.hostname)
        }
        names += service.dnsHostnames(context)
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    /// The IPv4 address for those names, looked up if named
    static func address(of deployment: Deployment, lookup: (String) async -> [String] = resolvedIPv4) async -> String? {
        let host = deployment.entry.host
        if isIPv4(host) { return host }
        guard !host.isEmpty else { return nil }
        return await lookup(host).first
    }

    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    /// Publishes through the saved DNS token, one line per zone
    @MainActor
    static func publish(_ service: any ManagedService, for deployment: Deployment) async -> [String] {
        guard deployment.scope.publishesAddressRecords, !deployment.services.contains(.cloudflared)
        else { return [] }
        let names = hostnames(of: service, in: deployment)
        guard !names.isEmpty else { return [] }
        guard let ip = await address(of: deployment) else {
            return [UIL10n.string("Point these names at the server: %@", names.joined(separator: ", "))]
        }
        let records = names.map { DNSRecord(name: $0, type: .a, value: ip) }
        guard let credential = DNSCredentials.shared.selected ?? DNSCredentials.shared.all.first,
              let token = await DNSCredentialTokenStore.load(credential), !token.isEmpty else {
            return [UIL10n.string("Add these DNS records: %@",
                                  records.map { "\($0.name) A \(ip)" }.joined(separator: ", "))]
        }
        var free: [DNSRecord] = []
        var notes: [String] = []
        for record in records {
            let found = await resolvedIPv4(record.name)
            if found.isEmpty || found.contains(ip) {
                free.append(record)
            } else {
                notes.append(UIL10n.string("%@ already points at %@ and was left alone. Change it by hand if this service should answer there.",
                                           record.name, found.joined(separator: ", ")))
            }
        }
        guard !free.isEmpty else { return notes }
        return await publish(free, zones: [deployment.domain] + deployment.additionalDomains,
                             provider: credential.kind.makeProvider(token: token)) + notes
    }

    static func resolvedIPv4(_ name: String) async -> [String] {
        await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_DGRAM
            var list: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(name, nil, &hints, &list) == 0, let first = list else { return [] }
            defer { freeaddrinfo(list) }
            var found: [String] = []
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let entry = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: buffer)
                    if !found.contains(address) { found.append(address) }
                }
                cursor = entry.pointee.ai_next
            }
            return found
        }.value
    }

    /// Removes the A records a removed service answered on
    @MainActor
    static func unpublish(_ service: any ManagedService, from deployment: Deployment,
                          keeping after: Deployment) async -> [String] {
        guard deployment.scope.publishesAddressRecords, !deployment.services.contains(.cloudflared),
              let ip = await address(of: deployment) else { return [] }
        let names = namesOnlyUsed(by: service, before: deployment, after: after)
        guard !names.isEmpty else { return [] }
        let byHand = UIL10n.string("Remove these DNS records by hand: %@",
                                   names.map { "\($0) A \(ip)" }.joined(separator: ", "))
        guard let credential = DNSCredentials.shared.selected ?? DNSCredentials.shared.all.first,
              let token = await DNSCredentialTokenStore.load(credential), !token.isEmpty else { return [byHand] }
        let provider = credential.kind.makeProvider(token: token)
        let zones = [deployment.domain] + deployment.additionalDomains
        var lines: [String] = []
        for zone in zones {
            let owned = names.filter { DNSRecordGenerator.zone(of: DNSRecord(name: $0, type: .a, value: ip), among: zones) == zone }
            guard !owned.isEmpty else { continue }
            do {
                let removed = try await provider.removeAddressRecords(named: owned, pointingAt: ip, zone: zone)
                if !removed.isEmpty {
                    lines.append(UIL10n.string("%@: removed %lld DNS record(s).", zone, removed.count))
                }
            } catch is DNSRemovalUnsupported {
                return [byHand]
            } catch {
                lines.append("\(zone): \(error.localizedDescription)")
            }
        }
        return lines
    }

    /// A name another installed service still answers on stays
    static func namesOnlyUsed(by service: any ManagedService, before: Deployment,
                              after: Deployment) -> [String] {
        let kept = Set(ServiceRegistry.all
            .filter { after.services.contains($0.id) && $0.id != service.id }
            .flatMap { hostnames(of: $0, in: after) }
            .map { $0.lowercased() })
        return hostnames(of: service, in: before).filter { !kept.contains($0.lowercased()) }
    }

    private static func publish(_ records: [DNSRecord], zones: [String],
                                provider: any DNSPublishingProvider) async -> [String] {
        var lines: [String] = []
        for zone in zones {
            let owned = records.filter { DNSRecordGenerator.zone(of: $0, among: zones) == zone }
            guard !owned.isEmpty else { continue }
            do {
                let outcomes = try await provider.publishReportingOutcomes(owned, zone: zone)
                let failed = outcomes.filter {
                    if case .failed = $0.result { return true }
                    return false
                }
                lines.append(failed.isEmpty
                    ? UIL10n.string("%@: DNS records are in place.", zone)
                    : UIL10n.string("%@: %lld DNS record(s) could not be published.", zone, failed.count))
            } catch {
                lines.append("\(zone): \(error.localizedDescription)")
            }
        }
        return lines
    }

    // MARK: - Asking before a change

    /// Names to add or remove, waiting for the user's yes
    struct Update: Identifiable {
        let id = UUID()
        let service: any ManagedService
        let before: Deployment
        let after: Deployment
        let add: [String]
        let remove: [String]

        var summary: String {
            var lines: [String] = []
            if !add.isEmpty { lines.append(UIL10n.string("Add: %@", add.joined(separator: ", "))) }
            if !remove.isEmpty { lines.append(UIL10n.string("Remove: %@", remove.joined(separator: ", "))) }
            return lines.joined(separator: "\n")
        }

        /// Writes the change with the token kept on this device
        @MainActor
        func apply() async -> [String] {
            if add.isEmpty {
                return await ServiceDNSPublisher.unpublish(service, from: before, keeping: after)
            }
            let lines = await ServiceDNSPublisher.publish(service, for: after)
            await DashboardViewModel(deployment: after).refreshCertificates()
            return lines
        }
    }

    /// What adding a service leaves DNS to catch up with
    static func pending(adding service: any ManagedService, to deployment: Deployment,
                        lookup: (String) async -> [String] = resolvedIPv4) async -> (Update?, [String]) {
        guard deployment.scope.publishesAddressRecords, !deployment.services.contains(.cloudflared) else { return (nil, []) }
        let names = hostnames(of: service, in: deployment)
        guard !names.isEmpty else { return (nil, []) }
        guard let ip = await address(of: deployment, lookup: lookup) else {
            return (nil, [UIL10n.string("Point these names at the server: %@", names.joined(separator: ", "))])
        }
        var missing: [String] = []
        for name in names where !(await lookup(name)).contains(ip) {
            missing.append(name)
        }
        guard !missing.isEmpty else { return (nil, []) }
        return (Update(service: service, before: deployment, after: deployment, add: missing, remove: []), [])
    }

    /// What removing a service leaves DNS to catch up with
    static func pending(removing service: any ManagedService, from before: Deployment, keeping after: Deployment,
                        lookup: (String) async -> [String] = resolvedIPv4) async -> Update? {
        guard before.scope.publishesAddressRecords, !before.services.contains(.cloudflared),
              let ip = await address(of: before, lookup: lookup) else { return nil }
        var stale: [String] = []
        for name in namesOnlyUsed(by: service, before: before, after: after) where (await lookup(name)).contains(ip) {
            stale.append(name)
        }
        guard !stale.isEmpty else { return nil }
        return Update(service: service, before: before, after: after, add: [], remove: stale)
    }
}
