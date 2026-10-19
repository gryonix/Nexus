package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupPlan
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.BackupWrapperSpec
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.RestoreSpec
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceDefaultHostnames
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class HomepageService : ManagedService {
    override val id = ServiceID.HOMEPAGE
    override val displayName = "Homepage"
    override val systemImage = "square.grid.2x2"
    override val category = ServiceCategory.DASHBOARD

    override val usesSharedAdminLogin = false
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** A small Next.js server */
    override val resources = ServiceResources(memoryMB = 256, diskGB = 1)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.homepageHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.HOMEPAGE, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.homepagePath
        val allowed = context.servedHostnames(hostname(context)).joinToString(",")
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              homepage:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  # Read out of the image's own middleware, not its docs: a
                  # request whose Host is not in this list is answered with
                  # HTTP 400 and nothing else. Caddy forwards the real Host,
                  # so every name of the site belongs here.
                  HOMEPAGE_ALLOWED_HOSTS: $allowed
                volumes:
                  - $path/config:/app/config
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_WEB_PORT"
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.homepagePath
        val lang = context.language
        return listOf(
            """
            log "Homepage: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path/config
            cd $path
            """.trimIndent(),
            """
            # The derived half of the configuration. Rewritten every run — a
            # start page that stopped listing a service installed last week is
            # the failure this service exists to prevent. Everything else in
            # the directory belongs to the owner and is created ONLY if absent.
            backup $path/config/services.yaml
            cat > $path/config/services.yaml <<'EOF_HOMEPAGE_SERVICES'
            @SERVICESYAML@
            EOF_HOMEPAGE_SERVICES
            backup $path/config/settings.yaml
            cat > $path/config/settings.yaml <<'EOF_HOMEPAGE_SETTINGS'
            @SETTINGSYAML@
            EOF_HOMEPAGE_SETTINGS
            # Homepage refuses to start without these files existing at all, so
            # they are created empty — and never rewritten, because from the
            # first edit on they are somebody's own page.
            for f in bookmarks.yaml widgets.yaml docker.yaml; do
              if [ ! -f "$path/config/${SH}f" ]; then
                printf '%s\n' '---' > "$path/config/${SH}f"
              fi
            done
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent().embedding(
                "SERVICESYAML" to servicesYAML(context),
                "SETTINGSYAML" to settingsYAML(context)
            )
        )
    }

    fun servicesYAML(context: ServiceContext): String {
        val lines = mutableListOf("---")
        for (category in ServiceRegistry.categories) {
            val shelf = ServiceRegistry.services(category) +
                ServiceRegistry.services(ServiceCategory.IMPLICIT)
                    .filter { it.displayCategory == category }
            val members = shelf.filter { service ->
                service.id != id &&
                    service.id in context.installedServices &&
                    service.webIngress(context) != null
            }
            if (members.isEmpty()) continue
            lines.add("- ${yamlScalar(category.title)}:")
            for (service in members) {
                val ingress = service.webIngress(context) ?: continue
                lines.add("    - ${yamlScalar(service.displayName)}:")
                lines.add("        href: https://${ingress.hostname}")
                lines.add("        description: ${yamlScalar(category.summary)}")
            }
        }
        return lines.joinToString("\n")
    }

    fun settingsYAML(context: ServiceContext): String {
        val layout = ServiceRegistry.categories
            .filter { category ->
                context.installedServices.any { serviceID ->
                    if (serviceID == id) return@any false
                    val member = ServiceRegistry.service(serviceID) ?: return@any false
                    if (member.webIngress(context) == null) return@any false
                    member.displayCategory == category
                }
            }
            .joinToString("\n  ") { "${yamlScalar(it.title)}:\n    style: row\n    columns: 3" }
        return """
        ---
        title: ${yamlScalar(context.domain)}
        headerStyle: boxed
        layout:
          @LAYOUT@
        """.trimIndent().embedding("LAYOUT" to layout)
    }

    /** A YAML scalar that cannot be read as anything else */
    fun yamlScalar(text: String): String = "'" + text.replace("'", "''") + "'"

    /** Nothing */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.homepagePath
        val lang = context.language
        return listOf("""
        echo "Homepage: https://${hostname(context)}"
        echo "  ${L10nServices.homepageGeneratedNote(lang)}: $path/config/services.yaml"
        echo "  ${L10nServices.homepageOwnEditsNote(lang)}: $path/config/bookmarks.yaml"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.homepagePath
        return ServiceActions(
            statusProbe = StatusProbe.Container(
                name = CONTAINER,
                list = PrivilegedCommand("/usr/bin/docker", "ps -a")
            ),
            restart = ServicePower.container(CONTAINER, "restart"),
            start = ServicePower.container(CONTAINER, "start"),
            stop = ServicePower.container(CONTAINER, "stop"),
            backup = BackupSpec.WrapperScript(BackupWrapperSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                run = ServiceCommand(
                    PrivilegedCommand(BackupWrapperSpec.WRAPPER_PATH, ""),
                    ServiceCommand.TimeoutClass.LONG,
                    streamsOutput = true
                ),
                plan = BackupPlan.Archive(ArchiveBackupPlan(
                    composeProject = COMPOSE_PROJECT,
                    dataPath = "$path/config",
                    databases = emptyList(),
                    quiesceServices = emptyList(),
                    encryptsByDefault = false,
                    sizePaths = listOf("$path/config")
                ))
            )),
            restore = RestoreSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                needsPassphrase = false,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
            )
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.homepagePath,
        dataPaths = listOf("${context.settings.homepagePath}/config.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "homepage"
        const val CONTAINER = "homepage"

        const val WEB_UI_PORT = 8093

        const val CONTAINER_WEB_PORT = 3000
        val WRAPPER_TARGET = ServiceID.HOMEPAGE.rawValue

        /** Exact pinned tag */
        const val IMAGE = "ghcr.io/gethomepage/homepage:v1.4.5"
    }
}
