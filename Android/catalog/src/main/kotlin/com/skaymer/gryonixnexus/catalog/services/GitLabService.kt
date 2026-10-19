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
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class GitLabService : ManagedService {
    override val id = ServiceID.GITLAB
    override val displayName = "GitLab"
    override val systemImage = "chevron.left.forwardslash.chevron.right"

    override val category = ServiceCategory.CODE
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 8192, diskGB = 25)

    /** Full web UI hostname */
    fun hostname(context: ServiceContext): String {
        val custom = context.settings.gitlabHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.GITLAB, context)
        } else {
            custom
        }
    }

    fun sshPort(context: ServiceContext): Int? =
        context.settings.gitlabSSHPort.takeIf { it > 0 }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.gitlabPath
        val host = hostname(context)
        val ssh = sshPort(context)
        val sshSetting = ssh?.let { "\n        gitlab_rails['gitlab_shell_ssh_port'] = $it" } ?: ""
        val sshPublish = ssh?.let { "\n      - \"$it:22\"" } ?: ""
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              gitlab:
                image: $IMAGE
                container_name: $CONTAINER_NAME
                restart: unless-stopped
                hostname: $host
                # Upstream's own compose example raises this: the stock 64 MB
                # of /dev/shm is not enough for the omnibus PostgreSQL.
                shm_size: "256m"
                environment:
                  # Passed separately so the secret stays in .env (0600) and
                  # never lands in docker-compose.yml; the omnibus config below
                  # reads it through ENV, which also keeps every literal `${SH}`
                  # out of a file docker compose interpolates.
                  GITLAB_ROOT_PASSWORD: ${SH}{GITLAB_ROOT_PASSWORD}
                  GITLAB_OMNIBUS_CONFIG: |
                    external_url 'https://$host'
                    # Caddy terminates TLS and proxies plain HTTP to the
                    # loopback port; without these two the bundled nginx binds
                    # HTTPS itself and answers the proxy with a redirect loop.
                    # Key names are VERSION-SPECIFIC and were read out of the
                    # pinned release's own gitlab.rb.template: master has since
                    # moved them under gitlab_rails['nginx'], and an omnibus
                    # that does not recognise a key simply ignores it — the
                    # failure would be a silently HTTPS-only nginx, not an error.
                    nginx['listen_port'] = 80
                    nginx['listen_https'] = false
                    # An https external_url turns omnibus' own Let's Encrypt
                    # client ON by default. It would race Caddy for the same
                    # name and burn that name's ACME failure quota, and the
                    # certificate it fought for is one nothing here serves.
                    letsencrypt['enable'] = false
                    # Applied on the FIRST reconfigure only (omnibus ignores it
                    # once the database is seeded), so a re-run never resets a
                    # password the user has since changed.
                    gitlab_rails['initial_root_password'] = ENV['GITLAB_ROOT_PASSWORD']
                    # The image otherwise writes the password it used into
                    # /etc/gitlab/initial_root_password and deletes it after
                    # 24 h. Ours is already in .env and in the install report —
                    # a third copy is one more place to leak it from, and one
                    # that disappears on its own schedule.
                    gitlab_rails['store_initial_root_password'] = false
                    gitlab_rails['display_initial_root_password'] = false
                    # The bundled Prometheus/exporter stack is the largest
                    # slice of idle memory here and duplicates the metrics
                    # collector this project installs on the host anyway.
                    prometheus_monitoring['enable'] = false
                    # Two workers is upstream's own guidance for a small
                    # install; the default scales to a machine nobody here has.
                    puma['worker_processes'] = 2@SSHSETTING@
                volumes:
                  - $path/config:/etc/gitlab
                  - $path/logs:/var/log/gitlab
                  - $path/data:/var/opt/gitlab
                  - /etc/localtime:/etc/localtime:ro
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:80"@SSHPUBLISH@
            """.trimIndent()
                .embedding("SSHSETTING" to sshSetting, "SSHPUBLISH" to sshPublish),
            envTemplate = """
            GITLAB_ROOT_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.gitlabPath
        val lang = context.language
        val signupMarker = "$path/.gryonixnexus-signup-closed"
        return listOf(
            """
            log "GitLab: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            """
            # GitLab ships with sign-up OPEN and there is no gitlab.rb key for
            # it — the setting lives in the database, so it can only be closed
            # after the first reconfigure has seeded one. On a public URL an
            # open forge is the whole server, which is why this step exists at
            # all.
            #
            # Nothing here is fatal and no output is discarded: the same rule
            # the mailcow API and Nextcloud occ blocks follow. This step sits
            # mid-install, and errexit here would take every remaining service
            # and the install key's revocation with it.
            GL_OUT=""
            GL_TIMEOUT=120
            gl_exec() { GL_OUT="${SH}(timeout "${SH}GL_TIMEOUT" docker exec $CONTAINER_NAME "${SH}@" 2>&1)"; }
            # Why the last call failed, bounded to one line: omnibus answers in
            # multi-line Chef output, and the app streams this log live.
            gl_why() { printf '%s' "${SH}GL_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of tries: each attempt can burn its own
            # timeout, so counting attempts makes the real wait unbounded.
            # First boot is a full omnibus reconfigure plus database migrations
            # — many minutes on a small ARM machine, which is exactly the wait
            # that looks like a hung install without a heartbeat.
            GL_READY=0
            GL_TRY=0
            GL_DEADLINE=${SH}((${SH}(date +%s) + 600))
            while [ "${SH}(date +%s)" -lt "${SH}GL_DEADLINE" ]; do
              # `gitlab-ctl status` reaches the runit services, so it stays red
              # until the reconfigure has actually defined and started them —
              # unlike the container, which reports up within seconds. Puma by
              # name because it is the one that serves the page.
              if gl_exec gitlab-ctl status && printf '%s' "${SH}GL_OUT" | grep -q '^run: puma'; then
                GL_READY=1
                break
              fi
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              GL_TRY=${SH}((GL_TRY + 1))
              if [ "${SH}((GL_TRY % 3))" -eq 0 ]; then
                log "${L10nServices.gitlabWaiting(lang)} (${SH}(gl_why))"
              fi
              sleep 10
            done
            if [ "${SH}GL_READY" -eq 1 ]; then
              if [ ! -f $signupMarker ]; then
                # A rails runner boots the entire Rails environment before it
                # executes anything — minutes on ARM, far past the probe's
                # timeout, so it gets its own.
                GL_TIMEOUT=300
                if gl_exec gitlab-rails runner "ApplicationSetting.last.update!(signup_enabled: false)"; then
                  : > $signupMarker
                else
                  log "${L10nServices.gitlabSignupCloseFailed(lang)} (${SH}(gl_why))"
                fi
              fi
            else
              log "${L10nServices.gitlabStillStarting(lang)} (${SH}(gl_why))"
            fi
            """.trimIndent()
        )
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> {
        val port = sshPort(context) ?: return emptyList()
        return listOf(FirewallPort(port, FirewallPort.Proto.TCP, comment = "GitLab git SSH"))
    }

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.gitlabPath
        val lang = context.language
        val host = hostname(context)
        val lines = mutableListOf(
            """echo "GitLab:       https://$host"""",
            """echo "  ${L10nServices.administratorLabel(lang)}: root"""",
            """echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^GITLAB_ROOT_PASSWORD=' $path/.env | cut -d= -f2-)"""",
            """echo "  ${L10nServices.gitlabRegistrationClosedNote(lang)}"""",
            """echo "  ${L10nServices.gitlabFirstStartNote(lang)}""""
        )
        val port = sshPort(context)
        if (port != null) {
            lines.add("""echo "  ${L10nServices.gitlabSSHNote(lang, host, port)}"""")
        } else {
            lines.add("""echo "  ${L10nServices.gitlabSSHDisabledNote(lang)}"""")
        }
        return listOf(lines.joinToString("\n"))
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.gitlabPath
        return ServiceActions(
            statusProbe = StatusProbe.ComposeProject(
                project = COMPOSE_PROJECT,
                list = PrivilegedCommand("/usr/bin/docker", "compose -p $COMPOSE_PROJECT ps")
            ),
            restart = ServicePower.compose(COMPOSE_PROJECT, "restart"),
            start = ServicePower.compose(COMPOSE_PROJECT, "start"),
            stop = ServicePower.compose(COMPOSE_PROJECT, "stop"),
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
                    dataPath = path,
                    databases = emptyList(),
                    quiesceServices = listOf(CONTAINER_NAME),
                    encryptsByDefault = false,
                    sizePaths = listOf("$path/config", "$path/data"),
                    excludes = listOf("${archiveSlot(path)}/logs")
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

    override fun updateSpec(context: ServiceContext) = UpdateSpec.OWN_UPDATER

    companion object {
        const val COMPOSE_PROJECT = "gitlab"

        /** Loopback port Caddy proxies to */
        const val WEB_UI_PORT = 8084
        const val CONTAINER_NAME = "gitlab"

        /** Service label the shared backup/restore wrapper dispatches on */
        val WRAPPER_TARGET = ServiceID.GITLAB.rawValue

        const val IMAGE = "gitlab/gitlab-ce:19.2.1-ce.0"

        fun archiveSlot(path: String): String =
            path.split("/").lastOrNull()?.takeIf { it.isNotEmpty() } ?: path
    }
}
