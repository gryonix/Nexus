package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.core.DNSPublishOutcome
import com.skaymer.gryonixnexus.core.DNSPublishingProvider
import com.skaymer.gryonixnexus.core.DNSRecord
import com.skaymer.gryonixnexus.core.DNSRemovalUnsupported
import com.skaymer.gryonixnexus.recipe.DNSRecordGenerator
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException

class HomeOnlyDNS(
    private val provider: () -> DNSPublishingProvider?,
    private val text: Text = Text(),
    private val resolve: suspend (String) -> List<String> = ServiceDNSPublisher::systemAddresses,
) {
    /** The sentences this reports in, from the app's strings */
    class Text(
        val removed: (String, Int) -> String = { zone, count -> "$zone: $count" },
        val restored: (String) -> String = { it },
        val notPublished: (String, Int) -> String = { zone, count -> "$zone: $count" },
    )

    enum class Action { REMOVE, RESTORE }

    /** Records to change by hand */
    data class Manual(val action: Action, val records: List<DNSRecord>) {
        val lines: List<String> get() = records.map { "${it.name} ${it.type.name} ${it.value}" }
    }

    sealed class Outcome {
        data class Done(val lines: List<String>) : Outcome()
        data class Failed(val lines: List<String>) : Outcome()
        data class ByHand(val manual: Manual) : Outcome()
    }

    suspend fun records(service: ManagedService, deployment: Deployment): List<DNSRecord> {
        val address = ServiceDNSPublisher.address(deployment)
            ?: deployment.entry.host.takeIf { it.isNotEmpty() }?.let { resolve(it).firstOrNull() ?: it }
            ?: return emptyList()
        return ServiceDNSPublisher.hostnames(service, deployment).map { DNSRecord(it, DNSRecord.RecordType.A, address) }
    }

    suspend fun change(action: Action, service: ManagedService, deployment: Deployment): Outcome {
        val records = records(service, deployment)
        val byHand = Outcome.ByHand(Manual(action, records))
        val publisher = provider()
        if (records.isEmpty() || !deployment.scope.publishesAddressRecords ||
            ServiceID.CLOUDFLARED in deployment.services || publisher == null
        ) {
            return byHand
        }
        val zones = listOf(deployment.domain) + deployment.additionalDomains
        val lines = mutableListOf<String>()
        var failed = false
        for (zone in zones) {
            val owned = records.filter { DNSRecordGenerator.zone(it, zones) == zone }
            if (owned.isEmpty()) continue
            try {
                lines += apply(action, owned, zone, publisher)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (unsupported: DNSRemovalUnsupported) {
                return byHand
            } catch (error: Exception) {
                failed = true
                lines += "$zone: ${error.message ?: error::class.simpleName}"
            }
        }
        return if (failed) Outcome.Failed(lines) else Outcome.Done(lines)
    }

    private suspend fun apply(
        action: Action,
        records: List<DNSRecord>,
        zone: String,
        publisher: DNSPublishingProvider,
    ): List<String> = when (action) {
        Action.REMOVE -> {
            val removed = publisher.removeAddressRecords(records.map { it.name }, records.first().value, zone)
            listOf(text.removed(zone, removed.size))
        }
        Action.RESTORE -> {
            val failed = publisher.publishReportingOutcomes(records, zone)
                .count { it.result is DNSPublishOutcome.Result.Failed }
            if (failed > 0) error(text.notPublished(zone, failed)) else listOf(text.restored(zone))
        }
    }
}
