public struct GitLabService: ManagedService {
    public static let composeProject = "gitlab"
    /// Loopback port Caddy proxies to
    public static let webUIPort = 8084
    public static let containerName = "gitlab"
    /// Service label the shared backup/restore wrapper dispatches on
    public static let wrapperTarget = ServiceID.gitlab.rawValue
    public static let image = "gitlab/gitlab-ce:19.2.1-ce.0"

    public let id = ServiceID.gitlab
    public let displayName = "GitLab"
    public let systemImage = "chevron.left.forwardslash.chevron.right"
    /// Empty ON PURPOSE, even though Forgejo covers the same need
    public let category = ServiceCategory.code
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 8192, diskGB: 25)

    public init() {}

    /// Full web UI hostname
    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.gitlabHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.gitlab, context) : custom
    }

    public func sshPort(_ context: ServiceContext) -> Int? {
        let port = context.settings.gitlabSSHPort
        return port > 0 ? port : nil
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.gitlabPath
        let host = hostname(context)
        let ssh = sshPort(context)
        let sshSetting = ssh.map { "\n        gitlab_rails['gitlab_shell_ssh_port'] = \($0)" } ?? ""
        let sshPublish = ssh.map { "\n      - \"\($0):22\"" } ?? ""
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              gitlab:
                image: \(Self.image)
                container_name: \(Self.containerName)
                restart: unless-stopped
                hostname: \(host)
                # Upstream's own compose example raises this: the stock 64 MB
                # of /dev/shm is not enough for the omnibus PostgreSQL.
                shm_size: "256m"
                environment:
                  # Passed separately so the secret stays in .env (0600) and
                  # never lands in docker-compose.yml; the omnibus config below
                  # reads it through ENV, which also keeps every literal `$`
                  # out of a file docker compose interpolates.
                  GITLAB_ROOT_PASSWORD: ${GITLAB_ROOT_PASSWORD}
                  GITLAB_OMNIBUS_CONFIG: |
                    external_url 'https://\(host)'
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
                    puma['worker_processes'] = 2\(sshSetting)
                volumes:
                  - \(path)/config:/etc/gitlab
                  - \(path)/logs:/var/log/gitlab
                  - \(path)/data:/var/opt/gitlab
                  - /etc/localtime:/etc/localtime:ro
                ports:
                  - "127.0.0.1:\(Self.webUIPort):80"\(sshPublish)
            """,
            envTemplate: """
            GITLAB_ROOT_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.gitlabPath
        let lang = context.language
        let signupMarker = "\(path)/.gryonixnexus-signup-closed"
        return [
            #"""
            log "GitLab: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
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
            gl_exec() { GL_OUT="$(timeout "$GL_TIMEOUT" docker exec \#(Self.containerName) "$@" 2>&1)"; }
            # Why the last call failed, bounded to one line: omnibus answers in
            # multi-line Chef output, and the app streams this log live.
            gl_why() { printf '%s' "$GL_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of tries: each attempt can burn its own
            # timeout, so counting attempts makes the real wait unbounded.
            # First boot is a full omnibus reconfigure plus database migrations
            # — many minutes on a small ARM machine, which is exactly the wait
            # that looks like a hung install without a heartbeat.
            GL_READY=0
            GL_TRY=0
            GL_DEADLINE=$(($(date +%s) + 600))
            while [ "$(date +%s)" -lt "$GL_DEADLINE" ]; do
              # `gitlab-ctl status` reaches the runit services, so it stays red
              # until the reconfigure has actually defined and started them —
              # unlike the container, which reports up within seconds. Puma by
              # name because it is the one that serves the page.
              if gl_exec gitlab-ctl status && printf '%s' "$GL_OUT" | grep -q '^run: puma'; then
                GL_READY=1
                break
              fi
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              GL_TRY=$((GL_TRY + 1))
              if [ "$((GL_TRY % 3))" -eq 0 ]; then
                log "\#(L10nServices.gitlabWaiting(lang)) ($(gl_why))"
              fi
              sleep 10
            done
            if [ "$GL_READY" -eq 1 ]; then
              if [ ! -f \#(signupMarker) ]; then
                # A rails runner boots the entire Rails environment before it
                # executes anything — minutes on ARM, far past the probe's
                # timeout, so it gets its own.
                GL_TIMEOUT=300
                if gl_exec gitlab-rails runner "ApplicationSetting.last.update!(signup_enabled: false)"; then
                  : > \#(signupMarker)
                else
                  log "\#(L10nServices.gitlabSignupCloseFailed(lang)) ($(gl_why))"
                fi
              fi
            else
              log "\#(L10nServices.gitlabStillStarting(lang)) ($(gl_why))"
            fi
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        guard let port = sshPort(context) else { return [] }
        return [FirewallPort(port, .tcp, comment: "GitLab git SSH")]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.gitlabPath
        let lang = context.language
        let host = hostname(context)
        var lines = [
            #"echo "GitLab:       https://\#(host)""#,
            #"echo "  \#(L10nServices.administratorLabel(lang)): root""#,
            #"""
            echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^GITLAB_ROOT_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
            """#,
            #"echo "  \#(L10nServices.gitlabRegistrationClosedNote(lang))""#,
            #"echo "  \#(L10nServices.gitlabFirstStartNote(lang))""#
        ]
        if let port = sshPort(context) {
            lines.append(#"echo "  \#(L10nServices.gitlabSSHNote(lang, host: host, port: port))""#)
        } else {
            lines.append(#"echo "  \#(L10nServices.gitlabSSHDisabledNote(lang))""#)
        }
        return [lines.joined(separator: "\n")]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.gitlabPath
        return ServiceActions(
            statusProbe: .composeProject(
                project: Self.composeProject,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                        arguments: "compose -p \(Self.composeProject) ps")
            ),
            restart: ServicePower.compose(project: Self.composeProject, "restart", timeoutClass: .restart),
            start: ServicePower.compose(project: Self.composeProject, "start", timeoutClass: .restart),
            stop: ServicePower.compose(project: Self.composeProject, "stop", timeoutClass: .restart),
            backup: .wrapperScript(BackupWrapperSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                run: ServiceCommand(
                    PrivilegedCommand(binaryPath: BackupWrapperSpec.wrapperPath, arguments: ""),
                    timeoutClass: .long,
                    streamsOutput: true
                ),
                plan: .archive(ArchiveBackupPlan(
                    composeProject: Self.composeProject,
                    dataPath: path,
                    databases: [],
                    quiesceServices: [Self.containerName],
                    encryptsByDefault: false,
                    sizePaths: ["\(path)/config", "\(path)/data"],
                    excludes: ["\(Self.archiveSlot(path: path))/logs"]
                ))
            )),
            restore: RestoreSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                needsPassphrase: false,
                privileged: PrivilegedCommand(binaryPath: RestoreSpec.wrapperPath, arguments: "")
            )
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec { .ownUpdater }

    static func archiveSlot(path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
