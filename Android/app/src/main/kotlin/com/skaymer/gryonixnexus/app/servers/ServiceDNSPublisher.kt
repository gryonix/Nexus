package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.core.DNSPublishOutcome
import com.skaymer.gryonixnexus.core.DNSPublishingProvider
import com.skaymer.gryonixnexus.core.DNSRecord
import com.skaymer.gryonixnexus.core.DNSRemovalUnsupported
import com.skaymer.gryonixnexus.recipe.DNSRecordGenerator
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException

/** Address records for a service added after setup */
class ServiceDNSPublisher(
    /** The saved DNS token's provider, or null without one */
    private val provider: () -> DNSPublishingProvider?,
    private val text: Text,
    private val resolve: suspend (String) -> List<String> = ::systemAddresses,
) {
    /** The sentences this reports in, from the app's strings */
    class Text(
        val point: (String) -> String,
        val manual: (String) -> String,
        val done: (String) -> String,
        val failed: (String, Int) -> String,
        val removed: (String, Int) -> String = { zone, count -> "$zone: $count" },
        val byHand: (String) -> String = { it },
        val elsewhere: (String, String) -> String = { name, address -> "$name $address" },
    )

    /** Publishes through the saved DNS token, one line per zone */
    suspend fun publish(service: ManagedService, deployment: Deployment): List<String> {
        if (!deployment.scope.publishesAddressRecords || ServiceID.CLOUDFLARED in deployment.services) {
            return emptyList()
        }
        val names = hostnames(service, deployment)
        if (names.isEmpty()) return emptyList()
        val ip = addressOf(deployment) ?: return listOf(text.point(names.joinToString(", ")))
        val records = names.map { DNSRecord(it, DNSRecord.RecordType.A, ip) }
        val publisher = provider()
            ?: return listOf(text.manual(records.joinToString(", ") { "${it.name} A $ip" }))
        val (free, taken) = records.partition { record ->
            val found = resolve(record.name)
            found.isEmpty() || ip in found
        }
        val notes = taken.map { text.elsewhere(it.name, resolve(it.name).joinToString(", ")) }
        if (free.isEmpty()) return notes
        return publish(free, listOf(deployment.domain) + deployment.additionalDomains, publisher) + notes
    }

    /** Names to add or remove, waiting for the user's yes */
    data class Update(
        val service: ManagedService,
        val before: Deployment,
        val after: Deployment,
        val add: List<String>,
        val remove: List<String>,
    )

    /** What adding a service leaves DNS to catch up with */
    suspend fun pendingAdd(service: ManagedService, deployment: Deployment): Pair<Update?, List<String>> {
        if (!deployment.scope.publishesAddressRecords || ServiceID.CLOUDFLARED in deployment.services) {
            return null to emptyList()
        }
        val names = hostnames(service, deployment)
        if (names.isEmpty()) return null to emptyList()
        val ip = addressOf(deployment) ?: return null to listOf(text.point(names.joinToString(", ")))
        val missing = names.filter { ip !in resolve(it) }
        if (missing.isEmpty()) return null to emptyList()
        return Update(service, deployment, deployment, missing, emptyList()) to emptyList()
    }

    /** What removing a service leaves DNS to catch up with */
    suspend fun pendingRemove(service: ManagedService, before: Deployment, after: Deployment): Update? {
        if (!before.scope.publishesAddressRecords || ServiceID.CLOUDFLARED in before.services) return null
        val ip = addressOf(before) ?: return null
        val stale = namesOnlyUsed(service, before, after).filter { ip in resolve(it) }
        if (stale.isEmpty()) return null
        return Update(service, before, after, emptyList(), stale)
    }

    /** Writes the change with the token kept on this device */
    suspend fun apply(update: Update): List<String> =
        if (update.add.isEmpty()) unpublish(update.service, update.before, update.after)
        else publish(update.service, update.after)

    /** A named entry is looked up */
    private suspend fun addressOf(deployment: Deployment): String? =
        address(deployment) ?: deployment.entry.host.takeIf { it.isNotEmpty() }?.let { resolve(it).firstOrNull() }

    /** Removes the A records a removed service answered on */
    suspend fun unpublish(service: ManagedService, deployment: Deployment, after: Deployment): List<String> {
        if (!deployment.scope.publishesAddressRecords || ServiceID.CLOUDFLARED in deployment.services) {
            return emptyList()
        }
        val ip = addressOf(deployment) ?: return emptyList()
        val names = namesOnlyUsed(service, deployment, after)
        if (names.isEmpty()) return emptyList()
        val byHand = text.byHand(names.joinToString(", ") { "$it A $ip" })
        val publisher = provider() ?: return listOf(byHand)
        val zones = listOf(deployment.domain) + deployment.additionalDomains
        val lines = mutableListOf<String>()
        for (zone in zones) {
            val owned = names.filter { DNSRecordGenerator.zone(DNSRecord(it, DNSRecord.RecordType.A, ip), zones) == zone }
            if (owned.isEmpty()) continue
            try {
                val removed = publisher.removeAddressRecords(owned, ip, zone)
                if (removed.isNotEmpty()) lines += text.removed(zone, removed.size)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (unsupported: DNSRemovalUnsupported) {
                return listOf(byHand)
            } catch (error: Exception) {
                lines += "$zone: ${error.message ?: error::class.simpleName}"
            }
        }
        return lines
    }

    private suspend fun publish(
        records: List<DNSRecord>,
        zones: List<String>,
        publisher: DNSPublishingProvider,
    ): List<String> = zones.mapNotNull { zone ->
        val owned = records.filter { DNSRecordGenerator.zone(it, zones) == zone }
        if (owned.isEmpty()) return@mapNotNull null
        try {
            val failed = publisher.publishReportingOutcomes(owned, zone)
                .count { it.result is DNSPublishOutcome.Result.Failed }
            if (failed == 0) text.done(zone) else text.failed(zone, failed)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            "$zone: ${error.message ?: error::class.simpleName}"
        }
    }

    companion object {
        /** What the system resolver says, without waiting long */
        suspend fun systemAddresses(name: String): List<String> = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            kotlinx.coroutines.withTimeoutOrNull(4_000) {
                runCatching {
                    java.net.InetAddress.getAllByName(name).filterIsInstance<java.net.Inet4Address>().mapNotNull { it.hostAddress }
                }.getOrDefault(emptyList())
            } ?: emptyList()
        }

        /** Names no other installed service still answers on */
        fun namesOnlyUsed(service: ManagedService, before: Deployment, after: Deployment): List<String> {
            val kept = ServiceRegistry.all
                .filter { it.id in after.services && it.id != service.id }
                .flatMap { hostnames(it, after) }
                .map { it.lowercase() }
                .toSet()
            return hostnames(service, before).filter { it.lowercase() !in kept }
        }

        fun hostnames(service: ManagedService, deployment: Deployment): List<String> {
            val context = deployment.serviceContext
            val names = mutableListOf<String>()
            service.webIngress(context)?.let { names += context.servedHostnames(it.hostname) }
            names += service.dnsHostnames(context)
            return names.distinctBy { it.lowercase() }
        }

        /** The IPv4 address those names point at */
        fun address(deployment: Deployment): String? {
            val host = deployment.entry.host
            val parts = host.split(".")
            return host.takeIf { parts.size == 4 && parts.all { part -> part.toIntOrNull() in 0..255 } }
        }
    }
}
