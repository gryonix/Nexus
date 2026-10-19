public struct TailscaleNodeService: ManagedService {
    public static let composeProject = "tailscale"
    public static let container = "tailscale"
    public static let wrapperTarget = ServiceID.tailscaleNode.rawValue
    /// Exact pinned tag
    public static let image = "tailscale/tailscale:v1.102.2"
    /// The mesh user its key is minted under
    public static let meshUser = "gryonixnexus"

    public let id = ServiceID.tailscaleNode
    public let displayName = "Tailscale"
    public let systemImage = "point.3.connected.trianglepath.dotted"
    public let category = ServiceCategory.mesh
    public let usesSharedAdminLogin = false
    public let requiresPublicDomain = false
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// One Go daemon
    public let resources = ServiceResources(memoryMB: 128, diskGB: 1)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String { "" }

    /// What this machine is called inside the mesh
    public func nodeName(_ context: ServiceContext) -> String {
        let custom = context.settings.tailscaleNodeName
        if !custom.isEmpty { return custom }
        return context.domain.split(separator: ".").first.map(String.init) ?? "server"
    }

    public static func joinsOwnControlServer(_ context: ServiceContext,
                                             installedServices: Set<ServiceID>) -> Bool {
        installedServices.contains(.headscale)
    }

    public func extraArgs(_ context: ServiceContext) -> String {
        let login = context.settings.tailscaleLoginServer.trimmingCharacters(in: .whitespaces)
        let dns = "--accept-dns=false"
        return login.isEmpty ? dns : "--login-server=\(login) \(dns)"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.tailscaleNodePath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              tailscale:
                image: \(Self.image)
                container_name: \(Self.container)
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
                  - \(path)/state:/var/lib/tailscale
                environment:
                  TS_STATE_DIR: /var/lib/tailscale
                  TS_HOSTNAME: \(nodeName(context))
                  # Read from .env, which is 0600 and written once.
                  TS_AUTHKEY: ${TS_AUTHKEY}
                  # --accept-dns=false: see the type comment. The server's own
                  # resolver must not depend on a container being up.
                  TS_EXTRA_ARGS: \(extraArgs(context))
            """,
            envTemplate: """
            TS_AUTHKEY=
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.tailscaleNodePath
        let lang = context.language
        let name = nodeName(context)
        return [
            #"""
            log "Mesh node: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)
            install -d -m 700 \#(path)/state
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
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
            if ! grep -q '_current-profile' \#(path)/state/tailscaled.state 2>/dev/null; then
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
                if timeout 10 docker exec \#(HeadscaleService.container) headscale users list >/dev/null 2>&1; then
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
              HS_USERS="$(timeout 30 docker exec \#(HeadscaleService.container) headscale users list -o json 2>/dev/null | tr -d ' \t\n' || true)"
              case "$HS_USERS" in
                *'"name":"\#(Self.meshUser)"'*) : ;;
                *) timeout 30 docker exec \#(HeadscaleService.container) headscale users create \#(Self.meshUser) >/dev/null 2>&1 || true
                   HS_USERS="$(timeout 30 docker exec \#(HeadscaleService.container) headscale users list -o json 2>/dev/null | tr -d ' \t\n' || true)" ;;
              esac
              # `preauthkeys create --user` takes the numeric ID, not the name
              # (checked against the CLI's own help).
              TS_USER_ID="$(printf '%s' "$HS_USERS" | sed -n 's/.*"id":\([0-9]*\),"name":"\#(Self.meshUser)".*/\1/p' || true)"
              TS_KEY=""
              if [ -n "$TS_USER_ID" ]; then
                # `--reusable`, and that word is the difference between a
                # node that survives a restart and one that never comes back.
                # A single-use key is spent by the FIRST registration attempt,
                # so a container that is restarted before it has written its
                # identity — a reboot, a `docker compose restart`, a join that
                # timed out — has nothing left to authenticate with and
                # crash-loops on "authkey expired" for ever. The key lives in
                # a 0600 .env on the host that minted it and expires in a day;
                # by then a joined node no longer reads it at all.
                TS_KEY="$(timeout 30 docker exec \#(HeadscaleService.container) headscale preauthkeys create \
                  --user "$TS_USER_ID" --reusable --expiration 24h -o json 2>/dev/null | tr -d ' \t\n' | sed -n 's/.*"key":"\([^"]*\)".*/\1/p' || true)"
              fi
              if [ -n "$TS_KEY" ]; then
                printf 'TS_AUTHKEY=%s\n' "$TS_KEY" > \#(path)/.env
                chmod 600 \#(path)/.env
              else
                log "  \#(L10nServices.meshNodeNoKeyNote(lang))"
              fi
            fi
            docker compose -p \#(Self.composeProject) up -d
            # Proof, not hope: ask the SERVER whether the node arrived. A
            # container that is up but never joined looks identical from here.
            for _ in 1 2 3 4 5 6 7 8 9 10; do
              if docker exec \#(HeadscaleService.container) headscale nodes list -o json 2>/dev/null | grep -q '"\#(name)"'; then
                log "  \#(L10nServices.meshNodeJoinedNote(lang)): \#(name)"
                break
              fi
              sleep 3
            done
            """#
        ]
    }

    /// None
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let name = nodeName(context)
        let base = HeadscaleService().baseDomain(context)
        return [#"""
        echo "\#(L10nServices.meshNodeTitle(lang)): \#(name).\#(base)"
        echo "  \#(L10nServices.meshNodeExplainNote(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        ServiceActions(
            statusProbe: .container(
                name: Self.container,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.container, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.container, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.container, "stop", timeoutClass: .restart)
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.tailscaleNodePath,
            dataPaths: [],
            backupDirs: []
        )
    }
}
