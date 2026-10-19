package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.EncryptedVolumeCommands
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
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class VaultwardenService : ManagedService {
    override val id = ServiceID.VAULTWARDEN
    override val displayName = "Vaultwarden"
    override val systemImage = "key"
    override val category = ServiceCategory.PASSWORDS
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.vaultwardenHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.VAULTWARDEN, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val container = context.settings.vaultwardenContainer
        val dataPath = context.settings.vaultwardenDataPath
        val signups = if (context.settings.vaultwardenAllowSignups) "true" else "false"
        return ComposeFile(
            directory = COMPOSE_DIRECTORY,
            composeContents = """
            services:
              vaultwarden:
                image: $IMAGE
                container_name: $container
                restart: unless-stopped
                environment:
                  DOMAIN: "https://${hostname(context)}"
                  SIGNUPS_ALLOWED: "$signups"
                  ADMIN_TOKEN: ${SH}{ADMIN_TOKEN}
                  IP_HEADER: X-Forwarded-For
                volumes:
                  - $dataPath:/data
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:80"
            """.trimIndent(),
            envTemplate = """
            ADMIN_TOKEN=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val signups = if (context.settings.vaultwardenAllowSignups) "true" else "false"
        val dataPath = context.settings.vaultwardenDataPath
        val container = context.settings.vaultwardenContainer
        return listOf("""
        log "Vaultwarden: ${L10nServices.serviceStarting(context.language)}"
        cd /opt/vaultwarden
        VW_CONFIG="$dataPath/config.json"
        VW_DOMAIN="https://${hostname(context)}"
        VW_RESTART=0
        if [ -f "${SH}VW_CONFIG" ]; then
          # The stored domain is only compared when the key is present: absent
          # means the compose environment still rules and needs no rewrite. When
          # it IS present it outranks env, so a reinstall onto another domain
          # would keep serving links to the old one.
          if ! jq -e --arg d "${SH}VW_DOMAIN" \
               '.signups_allowed == $signups and ((.domain // ${SH}d) == ${SH}d)' \
               "${SH}VW_CONFIG" >/dev/null 2>&1; then
            VW_TMP="${SH}(mktemp)"
            jq --arg d "${SH}VW_DOMAIN" \
               '.signups_allowed = $signups | if has("domain") then .domain = ${SH}d else . end' \
               "${SH}VW_CONFIG" > "${SH}VW_TMP"
            mv "${SH}VW_TMP" "${SH}VW_CONFIG"
            chmod 600 "${SH}VW_CONFIG"
            VW_RESTART=1
          fi
        fi
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        if [ "${SH}VW_RESTART" = "1" ]; then
          docker restart $container
        fi
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT, publicPaths = BITWARDEN_API_PATHS)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val signups = context.settings.vaultwardenAllowSignups
        val lang = context.language
        val openOrClosed = if (signups) L10nServices.vaultwardenSignupsOpen(lang)
                           else L10nServices.vaultwardenSignupsClosed(lang)
        return listOf("""
        echo "Vaultwarden:  https://${hostname(context)}"
        echo "  ${L10nServices.adminPanelLabel(lang)}: https://${hostname(context)}/admin"
        echo "  ${L10nServices.vaultwardenAdminTokenLabel(lang)}: ${SH}(grep '^ADMIN_TOKEN=' /opt/vaultwarden/.env | cut -d= -f2-)"
        echo "  ${L10nServices.vaultwardenRegisterNote(lang)}"
        echo "  $openOrClosed"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val container = context.settings.vaultwardenContainer
        return ServiceActions(
            statusProbe = StatusProbe.Container(
                name = container,
                list = PrivilegedCommand("/usr/bin/docker", "ps -a")
            ),
            restart = ServicePower.container(container, "restart"),
            start = ServicePower.container(container, "start"),
            stop = ServicePower.container(container, "stop"),
            backup = BackupSpec.EncryptedVolume(
                container = container,
                dataPath = context.settings.vaultwardenDataPath,
                backupDir = context.settings.vaultwardenBackupDir,
                stopStart = EncryptedVolumeCommands(
                    stop = PrivilegedCommand("/usr/bin/docker", "stop $container"),
                    start = PrivilegedCommand("/usr/bin/docker", "start $container")
                )
            ),
            restore = RestoreSpec(
                wrapperTarget = "vaultwarden",
                backupDir = context.settings.vaultwardenBackupDir,
                needsPassphrase = true,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
            )
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = COMPOSE_DIRECTORY,
        dataPaths = listOf(context.settings.vaultwardenDataPath,
                           "${context.settings.vaultwardenDataPath}.pre-restore-*"),
        backupDirs = listOf(context.settings.vaultwardenBackupDir),
        postSteps = listOf("rm -f /opt/vaultwarden-update.sh /opt/vaultwarden-update.sh.bak.* || true")
    )

    companion object {
        const val COMPOSE_PROJECT = "vaultwarden"
        const val COMPOSE_DIRECTORY = "/opt/vaultwarden"
        const val WEB_UI_PORT = 8082
        val BITWARDEN_API_PATHS = listOf(
            "/api/*", "/identity/*", "/notifications/*", "/icons/*",
            "/attachments/*", "/.well-known/*", "/alive", "/app-id.json",
        )

        /** Legacy path pinned by the original spec's sudoers list */
        const val IMAGE = "vaultwarden/server:latest"
    }
}
