package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.DNSRecord
import com.skaymer.gryonixnexus.core.bindTXTRData

class DNSRecordGenerator {
    /** Structured records for DNS provider implementations */
    fun records(context: MailContext): List<DNSRecord> {
        if (!context.publishesAddressRecords) return emptyList()
        val entry = context.entryPoint ?: return emptyList()
        val publicAddress = entry.publicAddress ?: return emptyList()

        val hostname = context.hostname
        val addressType = if (publicAddress.isIPv4) DNSRecord.RecordType.A
                          else DNSRecord.RecordType.AAAA
        val mailHostnames = if (context.hasMail) {
            listOf(hostname) + context.mirroredHostnames(hostname)
        } else {
            emptyList()
        }

        val records = mutableListOf<DNSRecord>()
        if (context.hasMail) records += mailRecords(context, mailHostnames, addressType, publicAddress.value)
        records += pointerHostRecord(context, addressType, publicAddress.value)
        records += serviceRecords(context, mailHostnames, addressType, publicAddress.value)
        return records
    }

    private fun mailRecords(
        context: MailContext,
        mailHostnames: List<String>,
        addressType: DNSRecord.RecordType,
        address: String,
    ): List<DNSRecord> {
        val hostname = context.hostname
        val language = context.language
        val singleHost = context.input.topology ==
            com.skaymer.gryonixnexus.catalog.Topology.SINGLE_HOST
        val records = mutableListOf<DNSRecord>()
        for (mailHostname in mailHostnames) {
            records.add(DNSRecord(
                name = mailHostname, type = addressType, value = address,
                comment = L10nGeneration.dnsMailHostComment(language, singleHost)
            ))
        }
        for (mailDomain in context.mailDomainNames) {
            records.add(DNSRecord(
                name = mailDomain, type = DNSRecord.RecordType.MX, value = hostname,
                priority = 10,
                comment = L10nGeneration.dnsMXComment(language, hostname)
            ))
            records.add(DNSRecord(
                name = mailDomain, type = DNSRecord.RecordType.TXT, value = "v=spf1 mx -all",
                comment = L10nGeneration.dnsSPFComment(language)
            ))
            records.add(DNSRecord(
                name = "_dmarc.$mailDomain", type = DNSRecord.RecordType.TXT,
                value = "v=DMARC1; p=quarantine; rua=mailto:postmaster@$mailDomain",
                comment = L10nGeneration.dnsDMARCComment(language)
            ))
            for (label in listOf("autodiscover", "autoconfig")) {
                records.add(DNSRecord(
                    name = "$label.$mailDomain", type = addressType, value = address,
                    comment = L10nGeneration.dnsAutoconfigComment(language)
                ))
            }
        }
        return records
    }

    private fun pointerHostRecord(
        context: MailContext,
        addressType: DNSRecord.RecordType,
        address: String,
    ): List<DNSRecord> {
        val hostname = context.hostname
        val domain = context.domainName
        val ptrHostname = context.ptrHostname
        if ((ptrHostname != hostname || !context.hasMail) &&
            ptrHostname.endsWith(".$domain")) {
            return listOf(DNSRecord(
                name = ptrHostname, type = addressType, value = address,
                comment = L10nGeneration.ptrForwardComment(context.language)
            ))
        }
        return emptyList()
    }

    private fun serviceRecords(
        context: MailContext,
        mailHostnames: List<String>,
        addressType: DNSRecord.RecordType,
        address: String,
    ): List<DNSRecord> {
        val hostname = context.hostname
        val language = context.language
        val singleHost = context.input.topology ==
            com.skaymer.gryonixnexus.catalog.Topology.SINGLE_HOST
        val records = mutableListOf<DNSRecord>()
        val serviceHostnames = context.allSelectedServices
            .flatMap { it.dnsHostnames(context.serviceContext) }
            .flatMap { listOf(it) + context.mirroredHostnames(it) }
            .toSet()
            .filter { it != hostname && it !in mailHostnames }
            .sorted()
        val serviceComment = L10nGeneration.dnsServiceHostsComment(language, singleHost)
        for (serviceHostname in serviceHostnames) {
            records.add(DNSRecord(
                name = serviceHostname, type = addressType, value = address,
                comment = serviceComment
            ))
        }
        for (service in context.allSelectedServices) {
            for (record in service.serviceRecords(context.serviceContext)) {
                records.add(DNSRecord.service(
                    name = record.name,
                    srv = DNSRecord.SRVData(record.priority, record.weight,
                                            record.port, record.target),
                    comment = serviceComment
                ))
            }
        }
        return records
    }

    fun generate(context: MailContext): List<Artifact> {
        if (!context.publishesAddressRecords) return emptyList()
        val entry = context.entryPoint ?: return emptyList()
        val publicAddress = entry.publicAddress ?: return emptyList()

        val domain = context.domainName
        val language = context.language
        val singleHost = context.input.topology ==
            com.skaymer.gryonixnexus.catalog.Topology.SINGLE_HOST

        val lines = mutableListOf<String>()
        var lastComment: String? = null
        for (record in records(context)) {
            val comment = record.comment
            if (comment != null && comment != lastComment) {
                lines.add("")
                lines.add("; $comment")
                lastComment = comment
            }
            lines.add(render(record))
        }

        var contents = "; " + L10nGeneration.dnsHeaderTitle(language, domain) + "\n" +
            "; " + L10nGeneration.dnsHeaderFormat(language)
        contents += "\n\n" + instructionBlock(context, domain, language) + "\n"
        contents += "\n" + lines.joinToString("\n")
        if (context.hasMail) {
            val dkimSelector = "dkim"
            contents += "\n\n"
            contents += "; " + L10nGeneration.dkimComment(language) + "\n" +
                "; $dkimSelector._domainkey.$domain.    IN TXT    " +
                "\"v=DKIM1; k=rsa; p=<" + L10nGeneration.dkimValuePlaceholder(language) + ">\""
        }
        contents += "\n\n"
        contents += "; " + L10nGeneration.ptrComment(language, singleHost) + "\n" +
            "; " + L10nGeneration.ptrTargetLine(language, publicAddress.value, context.ptrHostname)

        val artifacts = mutableListOf(
            Artifact(
                fileName = "dns-records.txt",
                suggestedPath = null,
                kind = ArtifactKind.DNS_RECORD,
                contents = contents,
                summary = if (context.hasMail) L10nGeneration.dnsSummaryMail(language)
                          else L10nGeneration.dnsSummaryServicesOnly(language),
                server = null
            )
        )
        val all = records(context)
        for (zoneName in context.mailDomainNames) {
            val owned = all.filter { zone(it, context.mailDomainNames) == zoneName }
            if (owned.isEmpty()) continue
            artifacts.add(generateZoneFile(zoneName, owned, language))
            artifacts.add(generateCSV(zoneName, owned, language))
        }
        return artifacts
    }

    private fun generateZoneFile(domain: String, records: List<DNSRecord>,
                                 language: AppLanguage): Artifact {
        val lines = records.map { renderZoneLine(it) }
        var contents = "; BIND zone file for $domain - import this at your DNS provider.\n" +
            "; SOA/NS are managed by the provider and are intentionally not included.\n" +
            "\$ORIGIN $domain.\n" +
            "\$TTL $ZONE_TTL"
        contents += "\n" + lines.joinToString("\n") + "\n"
        return Artifact(
            fileName = zoneFileName(domain),
            suggestedPath = null,
            kind = ArtifactKind.DNS_RECORD,
            contents = contents,
            summary = L10nGeneration.dnsZoneSummary(language),
            server = null
        )
    }

    private fun generateCSV(domain: String, records: List<DNSRecord>,
                            language: AppLanguage): Artifact {
        val lines = mutableListOf("type,name,value,ttl,priority")
        lines.addAll(records.map { renderCSVRow(it) })
        return Artifact(
            fileName = csvFileName(domain),
            suggestedPath = null,
            kind = ArtifactKind.DNS_RECORD,
            contents = lines.joinToString("\n") + "\n",
            summary = L10nGeneration.dnsCSVSummary(language),
            server = null
        )
    }

    private fun instructionBlock(context: MailContext, domain: String,
                                 language: AppLanguage): String {
        val block = mutableListOf("; " + L10nGeneration.dnsFormHeader(language), ";")
        val zones = context.mailDomainNames
        val all = records(context)
        for (zoneName in zones) {
            val owned = all.filter { zone(it, zones) == zoneName }
            if (owned.isEmpty()) continue
            if (zones.size > 1) {
                block.add("; ===== $zoneName =====")
                block.add(";")
            }
            for (record in owned) {
                val full = record.name
                val nameField: String
                val hint: String
                if (full == zoneName) {
                    nameField = "@"
                    hint = L10nGeneration.dnsRootNameHint(language, zoneName)
                } else if (full.endsWith(".$zoneName")) {
                    val label = full.dropLast(zoneName.length + 1)
                    nameField = label
                    hint = L10nGeneration.dnsNameHint(language, label, full)
                } else {
                    nameField = full
                    hint = ""
                }
                block.add(";   " + L10nGeneration.dnsFieldType(language) + ": " +
                          record.type.rawValue.uppercase())
                block.add(";   " + L10nGeneration.dnsFieldName(language) + ": " + nameField +
                          (if (hint.isEmpty()) "" else "   — $hint"))
                block.add(";   " + L10nGeneration.dnsFieldValue(language) + ": " + record.value)
                record.priority?.let {
                    block.add(";   " + L10nGeneration.dnsFieldPriority(language) + ": " + it)
                }
                block.add(";   " + L10nGeneration.dnsFieldTTL(language) + ": " +
                          L10nGeneration.dnsTTLAuto(language))
                block.add(";")
            }
            if (zones.size > 1) {
                for (line in L10nGeneration.dnsImportInstructions(
                    language, zoneFileName(zoneName), csvFileName(zoneName)
                ).split("\n")) {
                    block.add("; " + line)
                }
                block.add(";")
            }
        }
        block.add("; " + L10nGeneration.dnsCloudflareProxyWarning(language))
        block.add(";")
        if (zones.size == 1) {
            for (line in L10nGeneration.dnsImportInstructions(
                language, zoneFileName(domain), csvFileName(domain)
            ).split("\n")) {
                block.add("; " + line)
            }
        }
        return block.joinToString("\n")
    }

    private fun rdata(record: DNSRecord): String = when (record.type) {
        DNSRecord.RecordType.TXT -> bindTXTRData(record.value)
        DNSRecord.RecordType.MX -> "${record.value}."
        DNSRecord.RecordType.A, DNSRecord.RecordType.AAAA -> record.value
        DNSRecord.RecordType.SRV -> record.srv?.zoneRData ?: record.value
    }

    private fun typeField(record: DNSRecord): String =
        if (record.type == DNSRecord.RecordType.SRV) record.type.rawValue
        else record.priority?.let { "${record.type.rawValue} $it" } ?: record.type.rawValue

    private fun render(record: DNSRecord): String =
        "${record.name}.    IN ${typeField(record)}    ${rdata(record)}"

    private fun renderZoneLine(record: DNSRecord): String =
        "${record.name}.    $ZONE_TTL    IN ${typeField(record)}    ${rdata(record)}"

    /** CSV row (type,name,value,ttl,priority) with RFC4180 quoting */
    private fun renderCSVRow(record: DNSRecord): String {
        fun field(value: String): String {
            if (!value.contains(",") && !value.contains("\"") && !value.contains("\n")) return value
            return "\"" + value.replace("\"", "\"\"") + "\""
        }
        val priority = record.priority?.toString() ?: ""
        return listOf(record.type.rawValue, record.name, record.value,
                      ZONE_TTL.toString(), priority)
            .joinToString(",") { field(it) }
    }

    companion object {
        private const val ZONE_TTL = 3600

        /** Names of the two importable artifacts */
        fun zoneFileName(domain: String): String = "$domain-dns-zone.txt"
        fun csvFileName(domain: String): String = "$domain-dns-records.csv"

        /** Which zone a record belongs to */
        fun zone(record: DNSRecord, among: List<String>): String? =
            among.filter { record.name == it || record.name.endsWith(".$it") }
                .maxByOrNull { it.length }
    }
}
