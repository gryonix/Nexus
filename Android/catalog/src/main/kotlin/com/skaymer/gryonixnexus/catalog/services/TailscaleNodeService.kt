package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class TailscaleNodeService : ManagedService {
    override val id = ServiceID.TAILSCALE_NODE

    override val displayName = "Tailscale"
    override val systemImage = "point.3.connected.trianglepath.dotted"

    /** Both a product and an implicit member, deliberately */
    override val category = ServiceCategory.MESH
    override val usesSharedAdminLogin = false

    /** False, and the distinction matters */
    override val requiresPublicDomain = false
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** One Go daemon */
    override val resources = ServiceResources(memoryMB = 128, diskGB = 1)

    fun hostname(context: ServiceContext): String = ""

    /** What this machine is called inside the mesh */
    fun nodeName(context: ServiceContext): String {
        val custom = context.settings.tailscaleNodeName
        if (custom.isNotEmpty()) return custom
        return context.domain.split(".").firstOrNull()?.takeIf { it.isNotEmpty() } ?: "server"
    }

    fun extraArgs(context: ServiceContext): String {
        val login = context.settings.tailscaleLoginServer.trim()
        val dns = "--accept-dns=false"
        return if (login.isEmpty()) dns else "--login-server=$login $dns"
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.tailscaleNodePath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              tailscale:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                # The HOST's network stack, so the interface it creates belongs
                # to this machine rather than to a container nobody routes to.
                # With this, the host's own curl is
                # already routed into the mesh.
                network_mode: host
                cap_add:
                  - NET_ADMIN
                  - NET_RAW
                devices:
                  - /dev/net/tun:/dev/net/tun
                volumes:
                  # The node's identity. Losing it means re-joining as a new
                  # node and leaving a dead one behind in the server's list.
                  - $path/state:/var/lib/tailscale
                environment:
                  TS_STATE_DIR: /var/lib/tailscale
                  TS_HOSTNAME: ${nodeName(context)}
                  # Read from .env, which is 0600 and written once.
                  TS_AUTHKEY: ${SH}{TS_AUTHKEY}
                  # --accept-dns=false: see the type comment. The server's own
                  # resolver must not depend on a container being up.
                  TS_EXTRA_ARGS: ${extraArgs(context)}
            """.trimIndent(),
            envTemplate = """
            TS_AUTHKEY=
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.tailscaleNodePath
        val lang = context.language
        val name = nodeName(context)
        val headscale = HeadscaleService.CONTAINER
        return listOf("""
        log "Mesh node: ${L10nServices.serviceStarting(lang)}"
        install -d -m 755 $path
        install -d -m 700 $path/state
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        # The IDENTITY is the guard, not the presence of a state file, and
        # the difference is a crash loop. tailscaled writes
        # `tailscaled.state` the moment it starts — with nothing in it but
        # a machine key — so a node whose join FAILED leaves a non-empty
        # file behind and the old `-s` test read that as "already joined".
        # The re-run then skipped minting, the container retried the key it
        # had already spent, and every restart from then on died with
        # "authkey expired". A registered
        # profile is what a joined node has: `_current-profile` appears in
        # the file only once the control server has answered.
        if ! grep -q '_current-profile' $path/state/tailscaled.state 2>/dev/null; then
          # **Wait for the control server before asking it for anything.**
          # This step runs immediately after headscale's own `up -d`, and a
          # container that has started is not a server that is answering:
          # its CLI talks to a socket that appears a moment later. Every
          # call below then failed, and — because a bare assignment carries
          # the status of its command substitution — `set -e` killed the
          # whole install right here. Reported from the field as "I always
          # have to run the script a second time": the second run works
          # because headscale has been up since the first.
          for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            if timeout 10 docker exec $headscale headscale users list >/dev/null 2>&1; then
              break
            fi
            sleep 2
          done
          # The shapes below are the engine's REAL output, read off a
          # running v0.29.3 rather than guessed: the listing is pretty
          # printed with tabs, and `id` is a NUMBER (`"id": 1`), not the
          # quoted string an eye expects. Hence the whitespace strip
          # before any matching.
          # `|| true` INSIDE the substitution: an assignment takes the status
          # of its command substitution, and under `set -e` that is fatal —
          # the redirect to /dev/null hides the message, never the status.
          HS_USERS="${SH}(timeout 30 docker exec $headscale headscale users list -o json 2>/dev/null | tr -d ' \t\n' || true)"
          case "${SH}HS_USERS" in
            *'"name":"$MESH_USER"'*) : ;;
            *) timeout 30 docker exec $headscale headscale users create $MESH_USER >/dev/null 2>&1 || true
               HS_USERS="${SH}(timeout 30 docker exec $headscale headscale users list -o json 2>/dev/null | tr -d ' \t\n' || true)" ;;
          esac
          # `preauthkeys create --user` takes the numeric ID, not the name
          # (checked against the CLI's own help).
          TS_USER_ID="${SH}(printf '%s' "${SH}HS_USERS" | sed -n 's/.*"id":\([0-9]*\),"name":"$MESH_USER".*/\1/p' || true)"
          TS_KEY=""
          if [ -n "${SH}TS_USER_ID" ]; then
            # `--reusable`, and that word is the difference between a
            # node that survives a restart and one that never comes back.
            # A single-use key is spent by the FIRST registration attempt,
            # so a container that is restarted before it has written its
            # identity — a reboot, a `docker compose restart`, a join that
            # timed out — has nothing left to authenticate with and
            # crash-loops on "authkey expired" for ever. The key lives in
            # a 0600 .env on the host that minted it and expires in a day;
            # by then a joined node no longer reads it at all.
            TS_KEY="${SH}(timeout 30 docker exec $headscale headscale preauthkeys create \
              --user "${SH}TS_USER_ID" --reusable --expiration 24h -o json 2>/dev/null | tr -d ' \t\n' | sed -n 's/.*"key":"\([^"]*\)".*/\1/p' || true)"
          fi
          if [ -n "${SH}TS_KEY" ]; then
            printf 'TS_AUTHKEY=%s\n' "${SH}TS_KEY" > $path/.env
            chmod 600 $path/.env
          else
            log "  ${L10nServices.meshNodeNoKeyNote(lang)}"
          fi
        fi
        docker compose -p $COMPOSE_PROJECT up -d
        # Proof, not hope: ask the SERVER whether the node arrived. A
        # container that is up but never joined looks identical from here.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          if docker exec $headscale headscale nodes list -o json 2>/dev/null | grep -q '"$name"'; then
            log "  ${L10nServices.meshNodeJoinedNote(lang)}: $name"
            break
          fi
          sleep 3
        done
        """.trimIndent())
    }

    /** None */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val name = nodeName(context)
        val base = HeadscaleService().baseDomain(context)
        return listOf("""
        echo "${L10nServices.meshNodeTitle(lang)}: $name.$base"
        echo "  ${L10nServices.meshNodeExplainNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.Container(
            name = CONTAINER,
            list = PrivilegedCommand("/usr/bin/docker", "ps -a")
        ),
        restart = ServicePower.container(CONTAINER, "restart"),
        start = ServicePower.container(CONTAINER, "start"),
        stop = ServicePower.container(CONTAINER, "stop")
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.tailscaleNodePath,
        dataPaths = emptyList(),
        backupDirs = emptyList()
    )

    companion object {
        const val COMPOSE_PROJECT = "tailscale"
        const val CONTAINER = "tailscale"
        val WRAPPER_TARGET = ServiceID.TAILSCALE_NODE.rawValue

        /** Exact pinned tag */
        const val IMAGE = "tailscale/tailscale:v1.102.2"

        /** The mesh user its key is minted under */
        const val MESH_USER = "gryonixnexus"

        fun joinsOwnControlServer(context: ServiceContext,
                                  installedServices: Set<ServiceID>): Boolean =
            ServiceID.HEADSCALE in installedServices
    }
}
