import gryonixNexusCore
import ServerControl

/// DKIM records grouped by the mail domain they sign
enum DKIMZones {
    static func zones(from records: [DKIMRecord]) -> [ServiceConfigViewModel.DNSZonePreview] {
        let grouped = Dictionary(grouping: records) { zone(of: $0.name) }
        return grouped.keys.sorted().map { domain in
            ServiceConfigViewModel.DNSZonePreview(
                domain: domain,
                records: grouped[domain, default: []].map {
                    DNSRecord(name: $0.name, type: .txt, value: $0.value, comment: "DKIM")
                },
                zoneFile: nil,
                csvFile: nil)
        }
    }

    /// `dkim._domainkey.example.com` belongs to `example.com`
    static func zone(of name: String) -> String {
        guard let range = name.range(of: "._domainkey.") else { return name }
        return String(name[range.upperBound...])
    }
}
