package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ForwardedPorts
import com.skaymer.gryonixnexus.catalog.ManagedService

/** Which relay ports a closed-service check asks about */
object PublicPortProbe {
    /** The service's own TCP ports, never the shared web ports */
    fun ports(service: ManagedService, deployment: Deployment): List<Int> =
        ForwardedPorts.ownTCP(service, deployment.serviceContext)

    sealed class Verdict {
        data object Closed : Verdict()
        data class Open(val ports: List<Int>) : Verdict()
    }

    fun verdict(asked: List<Int>, open: List<Int>): Verdict {
        val leaks = asked.filter { it in open }.sorted()
        return if (leaks.isEmpty()) Verdict.Closed else Verdict.Open(leaks)
    }
}

object InternalCertificate {
    fun isPem(text: String): Boolean = text.contains("-----BEGIN CERTIFICATE-----") && text.contains("-----END CERTIFICATE-----")

    fun fileName(serverName: String): String {
        val slug = serverName.lowercase().map { if (it.isLetterOrDigit()) it else '-' }.joinToString("").trim('-')
        return "${slug.ifEmpty { "server" }}-root-ca.crt"
    }
}
