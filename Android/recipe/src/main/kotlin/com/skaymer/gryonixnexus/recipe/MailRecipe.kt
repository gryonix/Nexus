package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.GeneratedBundle
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.core.WireGuardDefaults

/** The recipe itself */
class MailRecipe(
    private val keyProvider: WireGuardKeyProvider = SecureRandomWireGuardKeyProvider()
) {
    val identifier = "mail"

    fun validate(input: MailRecipeInput) = MailInputValidator().validate(input)

    fun generate(input: MailRecipeInput): GeneratedBundle {
        validate(input)
        val context = MailContext(input)

        val artifacts = DNSRecordGenerator().generate(context).toMutableList()
        val serviceScripts = when (input.topology) {
            Topology.SINGLE_HOST -> {
                artifacts.add(SetupScripts.mailServer(context))
                SetupScripts.serviceScripts(context, context.mailHost?.publicAddress?.value ?: "")
            }
            Topology.VPS_RELAY_WITH_HOME_BACKEND -> {
                val vpsKeys = keyProvider.makeKeyPair(WireGuardKeySlot.VPS)
                val homeKeys = keyProvider.makeKeyPair(WireGuardKeySlot.HOME)
                artifacts.add(SetupScripts.vps(context, vpsKeys, homeKeys.publicKey))
                artifacts.add(SetupScripts.homeServer(context, homeKeys, vpsKeys.publicKey))
                val relayIP = context.server(ServerRole.VPS_RELAY)?.publicAddress?.value ?: ""
                val tunnel = L10nScripts.tunnelReportLine(context.language, "$relayIP:${WireGuardDefaults.LISTEN_PORT}")
                SetupScripts.serviceScripts(context, relayIP, listOf(tunnel))
            }
        }

        return GeneratedBundle(
            artifacts = artifacts,
            warnings = warnings(context),
            notes = notes(context),
            serviceScripts = serviceScripts,
        )
    }

    // MARK: - Warnings and application

    private fun warnings(context: MailContext): List<String> {
        val language = context.language
        val result = mutableListOf<String>()
        val entryIP = context.entryPoint?.publicAddress?.value ?: "<IP>"
        if (context.hasMail) {
            result.add(L10nGeneration.ptrWarning(language, entryIP, context.ptrHostname))
            result.add(L10nGeneration.port25Warning(language))
        }
        if (context.input.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) {
            result.add(L10nGeneration.wireGuardPrivateKeysWarning(language))
            result.add(L10nGeneration.fullTunnelWarning(language))
        }
        return result
    }

    private fun notes(context: MailContext): List<String> {
        val language = context.language
        val postSteps = L10nGeneration.postStepsServices(language)
        val dnsNotes = if (context.publishesAddressRecords) {
            listOf(
                if (context.input.topology == Topology.SINGLE_HOST) {
                    L10nGeneration.noteSingleHostDNS(language)
                } else {
                    L10nGeneration.noteSplitDNS(language)
                },
                L10nGeneration.noteDNSImportFiles(language)
            )
        } else {
            emptyList()
        }
        return when (context.input.topology) {
            Topology.SINGLE_HOST -> dnsNotes + listOf(
                L10nGeneration.noteSingleHostRun(language),
                postSteps
            )
            Topology.VPS_RELAY_WITH_HOME_BACKEND -> dnsNotes + listOf(
                L10nGeneration.noteSplitVPS(language),
                L10nGeneration.noteSplitHome(language),
                postSteps
            )
        }
    }

    companion object {
        fun revokeInstallKeyCommand(access: DashboardAccessInput, language: AppLanguage): String =
            DashboardAccessSections.revokeInstallKey(access, language)
    }
}
