package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.core.CloudflareError
import com.skaymer.gryonixnexus.core.CloudflareTunnelProvider
import com.skaymer.gryonixnexus.core.TunnelRoute
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException

/** A deployment's Cloudflare Tunnel: its connector token and its names */
class TunnelSetup(
    private val tunnelToken: () -> String?,
    private val dnsToken: () -> String?,
    private val tokenMissing: String,
    private val published: (Int) -> String,
) {
    /** The credential the server's connector runs with */
    suspend fun connectorToken(deployment: Deployment): String {
        val provider = provider(token())
        return try {
            provider.connectorToken(provider.findOrCreateTunnel(name(deployment)))
        } catch (refused: CloudflareError.InvalidToken) {
            throw IllegalStateException(tokenMissing)
        }
    }

    /** Every web name routed through the tunnel, as one sentence */
    suspend fun publishNames(deployment: Deployment): String {
        val token = token()
        val provider = provider(token)
        val tunnel = provider.findOrCreateTunnel(name(deployment))
        val names = webNames(deployment)
        provider.applyIngress(tunnel, names.map { TunnelRoute(it) })
        val own = names.filter { it.endsWith(".${deployment.domain}") }
        CloudflareTunnelProvider(dnsToken() ?: token, "").publishHostnames(own, tunnel, deployment.domain)
        return published(own.size)
    }

    private fun token(): String = tunnelToken() ?: throw IllegalStateException(tokenMissing)

    /** Provider for the tunnel token; account read via DNS token */
    private suspend fun provider(token: String): CloudflareTunnelProvider {
        val account = dnsToken()?.let { dns -> accountOrNull(dns) } ?: CloudflareTunnelProvider.accountID(token)
        return CloudflareTunnelProvider(token, account)
    }

    private suspend fun accountOrNull(token: String): String? = try {
        CloudflareTunnelProvider.accountID(token)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (refused: Exception) {
        null
    }

    companion object {
        /** One tunnel per deployment, named after its domain */
        fun name(deployment: Deployment): String = "gryonixnexus-" + deployment.domain.replace(".", "-")

        /** Web names to route through the tunnel, never mail hosts */
        fun webNames(deployment: Deployment): List<String> {
            val context = deployment.serviceContext
            return ServiceRegistry.all
                .filter { it.id in deployment.services && it.id !in ServiceRegistry.mailEngineIDs }
                .mapNotNull { it.webIngress(context) }
                .flatMap { context.servedHostnames(it.hostname) }
                .filterNot { it.startsWith("mail.") }
                .distinct()
        }
    }
}
