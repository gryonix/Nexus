package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import com.skaymer.gryonixnexus.catalog.services.VPNPanelService

class CatalogGoldenTest {
    private val json = Json { ignoreUnknownKeys = true }

    private val golden: Map<String, JsonObject> by lazy {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-catalog-golden.json")) {
            "the Swift-dumped catalog golden is missing"
        }.bufferedReader().readText()
        (json.parseToJsonElement(text) as JsonArray)
            .associate { entry ->
                val service = entry as JsonObject
                service.string("id") to service
            }
    }

    private fun JsonObject.string(key: String): String =
        this[key]!!.jsonPrimitive.content

    private fun JsonObject.optional(key: String): String? {
        val value = this[key] ?: return null
        val primitive = value.jsonPrimitive
        return if (!primitive.isString && primitive.content == "null") null else primitive.content
    }

    private fun JsonObject.list(key: String): List<String> =
        this[key]!!.jsonArray.map { it.jsonPrimitive.content }

    private fun JsonObject.int(key: String): Int = this[key]!!.jsonPrimitive.content.toInt()

    private fun JsonObject.bool(key: String): Boolean =
        this[key]!!.jsonPrimitive.content.toBoolean()

    /** The same deployment the Swift dumper described */
    private fun context(): ServiceContext = ServiceContext(
        domain = "example.com",
        additionalDomains = listOf("example.org"),
        sshUser = "admin",
        settings = ServiceSettings(
            minecraftJavaVersion = "1.21.4",
            minecraftJavaAcceptsEULA = true,
            minecraftJavaWhitelist = "dana,alex",
            minecraftJavaOperators = "dana",
            minecraftJavaMods = "fabric-api:bQZpGIz0,sodium:AANobbMO",
            minecraftBedrockAcceptsEULA = true
        ),
        language = AppLanguage.EN,
        installedServices = golden.keys.map { ServiceID(it) }.toSet()
    )

    @TestFactory
    fun `every ported service generates what Swift generates`(): List<DynamicTest> {
        assertTrue(ServiceRegistry.all.isNotEmpty(), "no services ported yet")
        val context = context()
        return ServiceRegistry.all.map { service ->
            DynamicTest.dynamicTest(service.id.rawValue) {
                val want = requireNotNull(golden[service.id.rawValue]) {
                    "${service.id.rawValue} is not in the Swift catalog — the id was mistyped"
                }
                assertIdentity(want, service, context)
                assertCompose(want, service, context)
                assertScripts(want, service, context)
                assertIngress(want, service, context)
                assertLifecycle(want, service, context)
                assertActions(want, service, context)
            }
        }
    }

    private fun assertIdentity(want: JsonObject, service: ManagedService, context: ServiceContext) {
        assertEquals(want.string("displayName"), service.displayName, "displayName")
        assertEquals(want.string("systemImage"), service.systemImage, "systemImage")
        assertEquals(want.string("category"), service.category.id, "category")
        assertEquals(want.bool("requiresPublicDomain"), service.requiresPublicDomain,
                     "requiresPublicDomain")
        assertEquals(want.bool("requiresHomeMachine"), service.requiresHomeMachine,
                     "requiresHomeMachine")
        assertEquals(want.bool("usesSharedAdminLogin"), service.usesSharedAdminLogin,
                     "usesSharedAdminLogin")
        assertEquals(want.int("memoryMB"), service.resources.memoryMB, "memoryMB")
        assertEquals(want.int("diskGB"), service.resources.diskGB, "diskGB")
        assertEquals((service.runtime as? ServiceRuntime.Docker)?.composeProject,
                     want.optional("runtimeProject"),
                     "compose project")
    }

    private fun assertCompose(want: JsonObject, service: ManagedService, context: ServiceContext) {
        val compose = service.composeFile(context)
        assertEquals(want.optional("composeDirectory"),
                     compose?.directory, "compose directory")
        assertEquals(want.optional("composeContents"),
                     compose?.composeContents, "compose contents")
        assertEquals(want.optional("envTemplate"),
                     compose?.envTemplate, ".env template")
    }

    private fun assertScripts(want: JsonObject, service: ManagedService, context: ServiceContext) {
        assertEquals(want.list("setupSteps"), service.setupSteps(context), "setup steps")
        val internal = context.copy(usesInternalTLS = true)
        assertEquals(want.optional("internalTLSComposeContents"),
                     service.composeFile(internal)?.composeContents, "compose contents with internal TLS")
        assertEquals(want.list("internalTLSSetupSteps"), service.setupSteps(internal), "setup steps with internal TLS")
        assertEquals(want.list("reportSteps"), service.reportSteps(context), "report steps")
        assertEquals(want.list("firewallPorts"),
                     service.firewallPorts(context)
                         .map { "${it.port}/${it.proto.wireValue} ${it.comment}" },
                     "firewall ports")
        assertEquals(want.list("dnsHostnames"), service.dnsHostnames(context),
                     "dns hostnames")
        assertEquals(want.list("serviceRecords"),
                     service.serviceRecords(context).map {
                         "${it.name} ${it.priority} ${it.weight} ${it.port} ${it.target}"
                     },
                     "service records")
        assertEquals(want.list("sudoersLines"), service.sudoersLines(context),
                     "sudoers lines")
    }

    private fun assertIngress(want: JsonObject, service: ManagedService, context: ServiceContext) {
        val ingress = service.webIngress(context)
        assertEquals(want.optional("webIngressHostname"),
                     ingress?.hostname, "ingress hostname")
        assertEquals(want.optional("webIngressPort"),
                     ingress?.upstreamPort?.toString(), "ingress port")
        assertEquals(want.optional("webIngressAdminGuard"),
                     ingress?.adminGuard?.toString(), "ingress admin guard")
        assertEquals(want.optional("webIngressUpstreamHTTPS"),
                     ingress?.upstreamHTTPS?.toString(), "ingress upstream https")
        assertEquals(want.list("webIngressPublicPaths"),
                     ingress?.publicPaths ?: emptyList<String>(), "ingress public paths")
    }

    private fun assertLifecycle(want: JsonObject, service: ManagedService, context: ServiceContext) {
        val update = service.updateSpec(context)
        assertEquals(want.list("updateImages"), update.images, "update images")
        assertEquals(want.string("updateFlavour"), update.flavour.swiftName(),
                     "update flavour")

        val uninstall = service.uninstallSpec(context)
        assertEquals(want.optional("uninstallComposeProject"),
                     uninstall.composeProject, "uninstall compose project")
        assertEquals(want.optional("uninstallConfigDirectory"),
                     uninstall.configDirectory, "uninstall config directory")
        assertEquals(want.list("uninstallDataPaths"), uninstall.dataPaths, "data paths")
        assertEquals(want.list("uninstallBackupDirs"), uninstall.backupDirs, "backup dirs")
        assertEquals(want.list("uninstallPreSteps"), uninstall.preSteps, "pre steps")
        assertEquals(want.list("uninstallPostSteps"), uninstall.postSteps, "post steps")
    }

    private fun assertActions(want: JsonObject, service: ManagedService, context: ServiceContext) {
        val actions = service.actions(context)
        assertEquals(want.list("actionCommands"), actionLines(actions),
                     "dashboard commands")
        assertEquals(want.optional("backupFlavour"), actions.backup?.swiftFlavour(),
                     "backup flavour")
        assertEquals(want.optional("backupListDirectory"), actions.backup?.listDirectory,
                     "backup list directory")
        assertEquals(want.optional("backupEncryptsByDefault"),
                     actions.backup?.encryptsByDefault?.toString(),
                     "backup encrypts by default")
        assertEquals(want.optional("backupWrapperTarget"),
                     actions.backup?.wrapper?.wrapperTarget, "backup wrapper target")
        assertEquals(want.optional("restoreWrapperTarget"),
                     actions.restore?.wrapperTarget, "restore wrapper target")
        assertEquals(want.optional("restoreBackupDir"),
                     actions.restore?.backupDir, "restore backup dir")
        assertEquals(want.optional("restoreNeedsPassphrase"),
                     actions.restore?.needsPassphrase?.toString(),
                     "restore needs passphrase")
    }

    private fun actionLines(actions: ServiceActions): List<String> {
        val lines = mutableListOf<String>()
        when (val probe = actions.statusProbe) {
            is StatusProbe.ComposeProject ->
                lines += "status\tcomposeProject:${probe.project}\t${probe.list.command}"
            is StatusProbe.Container ->
                lines += "status\tcontainer:${probe.name}\t${probe.list.command}"
        }
        actions.restart?.let { lines += actionLine("restart", it) }
        actions.start?.let { lines += actionLine("start", it) }
        actions.stop?.let { lines += actionLine("stop", it) }
        actions.logs?.let { lines += actionLine("logs", it) }
        when (val backup = actions.backup) {
            is BackupSpec.WrapperScript -> lines += actionLine("backup", backup.spec.run)
            is BackupSpec.EncryptedVolume -> {
                lines += "backupStop\t${backup.dataPath}\t${backup.stopStart.stop.command}"
                lines += "backupStart\t${backup.dataPath}\t${backup.stopStart.start.command}"
            }
            null -> Unit
        }
        actions.restore?.let {
            lines += "restore\t${it.wrapperTarget}\t${it.privileged.command}"
        }
        return lines
    }

    private fun actionLine(role: String, command: ServiceCommand): String =
        "$role\t${command.timeoutClass.swiftName()}\t${command.command}"

    private fun ServiceCommand.TimeoutClass.swiftName(): String = when (this) {
        ServiceCommand.TimeoutClass.QUICK -> "quick"
        ServiceCommand.TimeoutClass.RESTART -> "restart"
        ServiceCommand.TimeoutClass.LONG -> "long"
    }

    private fun BackupSpec.swiftFlavour(): String = when (this) {
        is BackupSpec.WrapperScript -> "wrapperScript"
        is BackupSpec.EncryptedVolume -> "encryptedVolume"
    }

    private fun UpdateSpec.Flavour.swiftName(): String = when (this) {
        UpdateSpec.Flavour.COMPOSE_PULL -> "composePull"
        UpdateSpec.Flavour.OWN_UPDATER -> "ownUpdater"
        UpdateSpec.Flavour.BUILT_ON_SERVER -> "builtOnServer"
    }

    @TestFactory
    fun `every service in the Swift catalog exists here too`(): List<DynamicTest> {
        val ported = ServiceRegistry.all.map { it.id.rawValue }.toSet()
        val missing = (golden.keys - ported).sorted()
        val extra = (ported - golden.keys).sorted()
        assertTrue(missing.isEmpty(),
                   "not ported yet: ${missing.joinToString(", ")}")
        assertTrue(extra.isEmpty(),
                   "here but not in the Swift catalog: ${extra.joinToString(", ")}")
        assertEquals(golden.keys.toList(), ServiceRegistry.all.map { it.id.rawValue },
                     "the catalog order differs between the two apps")
        return listOf(DynamicTest.dynamicTest("panel constants match the catalog") {
            val panel = requireNotNull(golden["vpn-panel"])
            assertEquals(panel.string("runtimeProject"), VPNPanelService.COMPOSE_PROJECT)
        })
    }
}
