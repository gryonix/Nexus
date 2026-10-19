import gryonixNexusCore
import ServiceCatalog

public struct DNSRecordGenerator: ArtifactGenerator {
    private static let zoneTTL = 3600

    /// Names of the two importable artifacts
    public static func zoneFileName(domain: String) -> String { "\(domain)-dns-zone.txt" }
    public static func csvFileName(domain: String) -> String { "\(domain)-dns-records.csv" }

    /// Which zone a record belongs to
    public static func zone(of record: DNSRecord, among domains: [String]) -> String? {
        domains
            .filter { record.name == $0 || record.name.hasSuffix(".\($0)") }
            .max { $0.count < $1.count }
    }

    public init() {}

    /// Structured records for DNSProvider implementations
    public func records(in context: MailContext) -> [DNSRecord] {
        guard context.publishesAddressRecords,
              let entry = context.entryPoint, let publicAddress = entry.publicAddress else {
            return []
        }
        let domain = context.domainName
        let hostname = context.hostname
        let addressType: DNSRecord.RecordType = publicAddress.isIPv4 ? .a : .aaaa
        let language = context.language
        let singleHost = context.input.topology == .singleHost

        let mailHostnames = context.hasMail
            ? [hostname] + context.mirroredHostnames(of: hostname)
            : []

        var records: [DNSRecord] = []
        if context.hasMail {
            for mailHostname in mailHostnames {
                records.append(DNSRecord(
                    name: mailHostname, type: addressType, value: publicAddress.value,
                    comment: L10nGeneration.dnsMailHostComment(language, singleHost: singleHost)
                ))
            }
            for mailDomain in context.mailDomainNames {
                records.append(DNSRecord(
                    name: mailDomain, type: .mx, value: hostname, priority: 10,
                    comment: L10nGeneration.dnsMXComment(language, hostname: hostname)
                ))
                records.append(DNSRecord(
                    name: mailDomain, type: .txt, value: "v=spf1 mx -all",
                    comment: L10nGeneration.dnsSPFComment(language)
                ))
                records.append(DNSRecord(
                    name: "_dmarc.\(mailDomain)", type: .txt,
                    value: "v=DMARC1; p=quarantine; rua=mailto:postmaster@\(mailDomain)",
                    comment: L10nGeneration.dnsDMARCComment(language)
                ))
                for label in ["autodiscover", "autoconfig"] {
                    records.append(DNSRecord(
                        name: "\(label).\(mailDomain)", type: addressType, value: publicAddress.value,
                        comment: L10nGeneration.dnsAutoconfigComment(language)
                    ))
                }
            }
        }

        let ptrHostname = context.ptrHostname
        if ptrHostname != hostname || !context.hasMail,
           ptrHostname.hasSuffix(".\(domain)") {
            records.append(DNSRecord(
                name: ptrHostname, type: addressType, value: publicAddress.value,
                comment: L10nGeneration.ptrForwardComment(language)
            ))
        }

        let serviceHostnames = Array(Set(
            context.allSelectedServices
                .flatMap { $0.dnsHostnames(context.serviceContext) }
                .flatMap { [$0] + context.mirroredHostnames(of: $0) }
        )).filter { $0 != hostname && !mailHostnames.contains($0) }.sorted()
        let serviceComment = L10nGeneration.dnsServiceHostsComment(language, singleHost: singleHost)
        for serviceHostname in serviceHostnames {
            records.append(DNSRecord(
                name: serviceHostname, type: addressType, value: publicAddress.value,
                comment: serviceComment
            ))
        }
        for service in context.allSelectedServices {
            for record in service.serviceRecords(context.serviceContext) {
                records.append(DNSRecord.service(
                    name: record.name,
                    srv: DNSRecord.SRVData(priority: record.priority, weight: record.weight,
                                           port: record.port, target: record.target),
                    comment: serviceComment
                ))
            }
        }
        return records
    }

    public func generate(in context: MailContext) throws -> [Artifact] {
        guard context.publishesAddressRecords,
              let entry = context.entryPoint, let publicAddress = entry.publicAddress else {
            return []
        }
        let domain = context.domainName
        let language = context.language
        let singleHost = context.input.topology == .singleHost

        var lines: [String] = []
        var lastComment: String?
        for record in records(in: context) {
            if let comment = record.comment, comment != lastComment {
                lines.append("")
                lines.append("; \(comment)")
                lastComment = record.comment
            }
            lines.append(render(record))
        }

        var contents = """
        ; \(L10nGeneration.dnsHeaderTitle(language, domain: domain))
        ; \(L10nGeneration.dnsHeaderFormat(language))
        """
        contents += "\n\n" + instructionBlock(for: context, domain: domain,
                                              language: language) + "\n"
        contents += "\n" + lines.joined(separator: "\n")
        if context.hasMail {
            let dkimSelector = "dkim"
            contents += "\n\n"
            contents += """
            ; \(L10nGeneration.dkimComment(language))
            ; \(dkimSelector)._domainkey.\(domain).    IN TXT    "v=DKIM1; k=rsa; p=<\(L10nGeneration.dkimValuePlaceholder(language))>"
            """
        }
        contents += "\n\n"
        contents += """
        ; \(L10nGeneration.ptrComment(language, singleHost: singleHost))
        ; \(L10nGeneration.ptrTargetLine(language, ip: publicAddress.value, hostname: context.ptrHostname))
        """

        var artifacts = [
            Artifact(
                fileName: "dns-records.txt",
                suggestedPath: nil,
                kind: .dnsRecord,
                contents: contents,
                summary: context.hasMail
                    ? L10nGeneration.dnsSummaryMail(language)
                    : L10nGeneration.dnsSummaryServicesOnly(language),
                server: nil
            )
        ]
        let all = records(in: context)
        for zoneName in context.mailDomainNames {
            let owned = all.filter { Self.zone(of: $0, among: context.mailDomainNames) == zoneName }
            guard !owned.isEmpty else { continue }
            artifacts.append(generateZoneFile(domain: zoneName, records: owned,
                                              language: language))
            artifacts.append(generateCSV(domain: zoneName, records: owned, language: language))
        }
        return artifacts
    }

    private func generateZoneFile(domain: String, records: [DNSRecord],
                                  language: AppLanguage) -> Artifact {
        let lines = records.map(renderZoneLine)
        var contents = """
        ; BIND zone file for \(domain) - import this at your DNS provider.
        ; SOA/NS are managed by the provider and are intentionally not included.
        $ORIGIN \(domain).
        $TTL \(Self.zoneTTL)
        """
        contents += "\n" + lines.joined(separator: "\n") + "\n"
        return Artifact(
            fileName: Self.zoneFileName(domain: domain),
            suggestedPath: nil,
            kind: .dnsRecord,
            contents: contents,
            summary: L10nGeneration.dnsZoneSummary(language),
            server: nil
        )
    }

    private func generateCSV(domain: String, records: [DNSRecord],
                             language: AppLanguage) -> Artifact {
        var lines = ["type,name,value,ttl,priority"]
        lines.append(contentsOf: records.map(renderCSVRow))
        return Artifact(
            fileName: Self.csvFileName(domain: domain),
            suggestedPath: nil,
            kind: .dnsRecord,
            contents: lines.joined(separator: "\n") + "\n",
            summary: L10nGeneration.dnsCSVSummary(language),
            server: nil
        )
    }

    private func instructionBlock(for context: MailContext, domain: String,
                                  language: AppLanguage) -> String {
        var block = ["; " + L10nGeneration.dnsFormHeader(language), ";"]
        let zones = context.mailDomainNames
        let all = records(in: context)
        for zoneName in zones {
            let owned = all.filter { Self.zone(of: $0, among: zones) == zoneName }
            guard !owned.isEmpty else { continue }
            if zones.count > 1 {
                block.append("; ===== \(zoneName) =====")
                block.append(";")
            }
            for record in owned {
                let full = record.name
                let nameField: String
                let hint: String
                if full == zoneName {
                    nameField = "@"
                    hint = L10nGeneration.dnsRootNameHint(language, domain: zoneName)
                } else if full.hasSuffix(".\(zoneName)") {
                    let label = String(full.dropLast(zoneName.count + 1))
                    nameField = label
                    hint = L10nGeneration.dnsNameHint(language, label: label, full: full)
                } else {
                    nameField = full
                    hint = ""
                }
                block.append(";   \(L10nGeneration.dnsFieldType(language)): \(record.type.rawValue.uppercased())")
                block.append(";   \(L10nGeneration.dnsFieldName(language)): \(nameField)"
                             + (hint.isEmpty ? "" : "   — \(hint)"))
                block.append(";   \(L10nGeneration.dnsFieldValue(language)): \(record.value)")
                if let priority = record.priority {
                    block.append(";   \(L10nGeneration.dnsFieldPriority(language)): \(priority)")
                }
                block.append(";   \(L10nGeneration.dnsFieldTTL(language)): \(L10nGeneration.dnsTTLAuto(language))")
                block.append(";")
            }
            if zones.count > 1 {
                for line in L10nGeneration.dnsImportInstructions(
                    language, zoneFile: Self.zoneFileName(domain: zoneName),
                    csvFile: Self.csvFileName(domain: zoneName)
                ).split(separator: "\n", omittingEmptySubsequences: false) {
                    block.append("; " + line)
                }
                block.append(";")
            }
        }
        block.append("; " + L10nGeneration.dnsCloudflareProxyWarning(language))
        block.append(";")
        if zones.count == 1 {
            for line in L10nGeneration.dnsImportInstructions(
                language, zoneFile: Self.zoneFileName(domain: domain),
                csvFile: Self.csvFileName(domain: domain)
            ).split(separator: "\n", omittingEmptySubsequences: false) {
                block.append("; " + line)
            }
        }
        return block.joined(separator: "\n")
    }

    private func render(_ record: DNSRecord) -> String {
        let value: String
        switch record.type {
        case .txt: value = bindTXTRData(record.value)
        case .mx: value = "\(record.value)."
        case .a, .aaaa: value = record.value
        case .srv: value = record.srv?.zoneRData ?? record.value
        }
        let typeField = record.type == .srv
            ? record.type.rawValue
            : (record.priority.map { "\(record.type.rawValue) \($0)" } ?? record.type.rawValue)
        return "\(record.name).    IN \(typeField)    \(value)"
    }

    private func renderZoneLine(_ record: DNSRecord) -> String {
        let value: String
        switch record.type {
        case .txt: value = bindTXTRData(record.value)
        case .mx: value = "\(record.value)."
        case .a, .aaaa: value = record.value
        case .srv: value = record.srv?.zoneRData ?? record.value
        }
        let typeField = record.type == .srv
            ? record.type.rawValue
            : (record.priority.map { "\(record.type.rawValue) \($0)" } ?? record.type.rawValue)
        return "\(record.name).    \(Self.zoneTTL)    IN \(typeField)    \(value)"
    }

    /// CSV row (type,name,value,ttl,priority) with RFC4180 quoting
    private func renderCSVRow(_ record: DNSRecord) -> String {
        func field(_ value: String) -> String {
            guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        let priority = record.priority.map(String.init) ?? ""
        return [record.type.rawValue, record.name, record.value, String(Self.zoneTTL), priority]
            .map(field)
            .joined(separator: ",")
    }
}
