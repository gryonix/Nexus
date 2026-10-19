package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.DNSRecord
import com.skaymer.gryonixnexus.recipe.ConfigurationExportFormat
import com.skaymer.gryonixnexus.recipe.DNSRecordGenerator
import com.skaymer.gryonixnexus.recipe.MailContext
import com.skaymer.gryonixnexus.recipe.MailRecipeInput
import com.skaymer.gryonixnexus.recipe.OpenPortRequirement
import com.skaymer.gryonixnexus.recipe.OpenPortsSummary
import com.skaymer.gryonixnexus.servercontrol.Deployment

object ConfigurationExport {
    data class DNSZone(
        val domain: String,
        val records: List<DNSRecord>,
        val copyText: String,
        val zoneFile: Artifact?,
        val csvFile: Artifact?,
    )

    data class PortsBundle(
        val requirements: List<OpenPortRequirement>,
        val copyText: String,
        val txtFile: Artifact,
        val csvFile: Artifact,
    )

    data class Bundle(val dns: List<DNSZone>, val ports: PortsBundle?)

    /** Both artefact sets for a deployment, best-effort */
    fun build(
        deployment: Deployment,
        recorded: ConfiguratorForm? = null,
        portsTxtSummary: String,
        portsCsvSummary: String,
    ): Bundle {
        val input = input(deployment, recorded) ?: return Bundle(emptyList(), null)
        return Bundle(dns = dnsZones(input), ports = ports(input, portsTxtSummary, portsCsvSummary))
    }

    fun preview(form: ConfiguratorForm): List<DNSZone> {
        val input = runCatching { form.toInput() }.getOrNull() ?: return emptyList()
        return dnsZones(input)
    }

    private fun input(deployment: Deployment, recorded: ConfiguratorForm?): MailRecipeInput? {
        val form = recorded ?: ConfiguratorForm.of(deployment)
        return runCatching { form.toInput() }.getOrNull()
    }

    private fun dnsZones(input: MailRecipeInput): List<DNSZone> {
        val context = MailContext(input)
        val generator = DNSRecordGenerator()
        val artifacts = runCatching { generator.generate(context) }.getOrDefault(emptyList())
        val all = generator.records(context)
        val zones = context.mailDomainNames
        return zones.mapNotNull { zoneName ->
            val owned = all.filter { DNSRecordGenerator.zone(it, zones) == zoneName }
            if (owned.isEmpty()) return@mapNotNull null
            DNSZone(
                domain = zoneName,
                records = owned,
                copyText = ConfigurationExportFormat.recordsText(owned, zoneName),
                zoneFile = artifacts.firstOrNull {
                    it.fileName == DNSRecordGenerator.zoneFileName(zoneName)
                },
                csvFile = artifacts.firstOrNull {
                    it.fileName == DNSRecordGenerator.csvFileName(zoneName)
                },
            )
        }
    }

    private fun ports(
        input: MailRecipeInput,
        txtSummary: String,
        csvSummary: String,
    ): PortsBundle? {
        val requirements = OpenPortsSummary.entryHostPorts(input)
        if (requirements.isEmpty()) return null
        return PortsBundle(
            requirements = requirements,
            copyText = ConfigurationExportFormat.portsText(requirements),
            txtFile = ConfigurationExportFormat.portsTextArtifact(requirements, txtSummary),
            csvFile = ConfigurationExportFormat.portsCSVArtifact(requirements, csvSummary),
        )
    }
}
