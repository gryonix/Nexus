package com.skaymer.gryonixnexus.app.dns

import com.skaymer.gryonixnexus.app.configurator.ConfigurationExport
import com.skaymer.gryonixnexus.core.DNSRecord

import com.skaymer.gryonixnexus.servercontrol.DKIMRecord

/** DKIM records grouped by the mail domain they sign */
object DKIMZones {
    fun zones(records: List<DKIMRecord>): List<ConfigurationExport.DNSZone> =
        records.groupBy { zoneOf(it.name) }.toSortedMap().map { (domain, owned) ->
            ConfigurationExport.DNSZone(
                domain = domain,
                records = owned.map { DNSRecord(it.name, DNSRecord.RecordType.TXT, it.value, comment = "DKIM") },
                copyText = "",
                zoneFile = null,
                csvFile = null,
            )
        }

    /** `dkim._domainkey.example.com` belongs to `example.com` */
    fun zoneOf(name: String): String = name.substringAfter("._domainkey.", name)
}
