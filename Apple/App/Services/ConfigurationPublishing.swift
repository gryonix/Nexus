import Foundation
import gryonixNexusCore
import ServerControl
import ServiceCatalog

/// The records the configuration screen publishes, per zone
enum ConfigurationPublishing {
    static func zones(dns: [ConfigurationExport.DNSZone], dkim: [DKIMRecord],
                      deployment: Deployment) -> [ServiceConfigViewModel.DNSZonePreview] {
        let addressesAllowed = deployment.scope.publishesAddressRecords
            && !deployment.services.contains(.cloudflared)
        var byZone: [String: [DNSRecord]] = [:]
        for zone in dns {
            var records = zone.records
            if let entry = entryRecord(host: deployment.entry.host, zone: zone.domain, records: records) {
                records.append(entry)
            }
            byZone[zone.domain, default: []] += records.filter {
                addressesAllowed || ($0.type != .a && $0.type != .aaaa)
            }
        }
        for zone in DKIMZones.zones(from: dkim) {
            byZone[zone.domain, default: []] += zone.records
        }
        return byZone.keys.sorted().compactMap { domain in
            guard let records = byZone[domain], !records.isEmpty else { return nil }
            return ServiceConfigViewModel.DNSZonePreview(domain: domain, records: records,
                                                         zoneFile: nil, csvFile: nil)
        }
    }

    /// The name the app connects by, pointed at the server
    static func entryRecord(host rawHost: String, zone: String, records: [DNSRecord]) -> DNSRecord? {
        let host = rawHost.trimmingCharacters(in: .whitespaces).lowercased()
        let zone = zone.lowercased()
        guard host == zone || host.hasSuffix(".\(zone)"),
              !records.contains(where: { $0.name.lowercased() == host && ($0.type == .a || $0.type == .aaaa) }),
              let address = records.first(where: { $0.type == .a || $0.type == .aaaa })
        else { return nil }
        return DNSRecord(name: host, type: address.type, value: address.value)
    }
}
