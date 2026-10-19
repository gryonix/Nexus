public struct XrayRealityService: ManagedService {
    public static let composeProject = "xray"
    public static let containerName = "xray"
    public static let image = "ghcr.io/xtls/xray-core:26.7.11"
    public static let containerConfigDir = "/usr/local/etc/xray"

    public let id = ServiceID.xrayReality
    public let displayName = "VLESS / Reality"
    public let systemImage = "eye.slash"
    public let category = ServiceCategory.vpn
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)

    public static let suggestedSites = [
        "www.apple.com", "www.microsoft.com", "www.cloudflare.com", "dl.google.com",
        "www.samsung.com", "www.amazon.com", "www.nvidia.com", "addons.mozilla.org",
    ]

    public static func normalisedSite(_ text: String) -> String? {
        let site = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels = site.split(separator: ".", omittingEmptySubsequences: false)
        guard site.count <= 253, labels.count >= 2 else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let valid = labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy(allowed.contains)
        }
        return valid ? site : nil
    }

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.vpnHostname
        return custom.isEmpty ? "vpn.\(context.domain)" : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.xrayRealityPath
        let port = context.settings.xrayRealityPort
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              xray:
                image: \(Self.image)
                container_name: \(Self.containerName)
                restart: unless-stopped
                # Run as root (0:0): config.json is chmod 600 root-owned (setup
                # and the panel both keep it 600, since it holds the REALITY
                # private key), and the image runs as a non-root user that would
                # otherwise get "permission denied" reading it.
                user: "0:0"
                volumes:
                  - \(path)/config:\(Self.containerConfigDir):ro
                ports:
                  - "\(port):\(port)/tcp"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.xrayRealityPath
        let port = context.settings.xrayRealityPort
        let sni = context.settings.xrayRealitySNI
        let host = hostname(context)
        let lang = context.language
        return [#"""
        log "VLESS/Reality: \#(L10nServices.serviceStarting(lang))"
        install -d \#(path)/config
        cd \#(path)
        # First run only: generate the UUID, the x25519 keypair and a shortId
        # on this server, then bake them into the config and the client link.
        if [ ! -f config/config.json ]; then
          docker pull -q \#(Self.image) >/dev/null
          XRAY_UUID="$(docker run --rm \#(Self.image) uuid | tr -d '\r\n')"
          XRAY_KEYS="$(docker run --rm \#(Self.image) x25519)"
          # Format changed across releases; accept "PrivateKey:" + "Password
          # (PublicKey):" (26.7), plain "Password:" and the older
          # "Private key:"/"Public key:". [^:]* swallows the "(PublicKey)" part.
          XRAY_PRIV="$(printf '%s\n' "$XRAY_KEYS" | sed -n -e 's/^PrivateKey:[[:space:]]*//p' -e 's/^Private key:[[:space:]]*//p' | head -n1)"
          XRAY_PUB="$(printf '%s\n' "$XRAY_KEYS" | sed -n -e 's/^Password[^:]*:[[:space:]]*//p' -e 's/^Public key:[[:space:]]*//p' | head -n1)"
          XRAY_SID="$(openssl rand -hex 8)"
          [ -n "$XRAY_PRIV" ] && [ -n "$XRAY_PUB" ] || fail "xray x25519 returned an empty key"
          cat > config/config.json <<EOF_XRAY_CONFIG
        {
            "log": { "loglevel": "warning" },
            "inbounds": [
                {
                    "listen": "0.0.0.0",
                    "port": \#(port),
                    "protocol": "vless",
                    "settings": {
                        "clients": [ { "id": "${XRAY_UUID}", "flow": "xtls-rprx-vision" } ],
                        "decryption": "none"
                    },
                    "streamSettings": {
                        "network": "tcp",
                        "security": "reality",
                        "realitySettings": {
                            "dest": "\#(sni):443",
                            "serverNames": [ "\#(sni)" ],
                            "privateKey": "${XRAY_PRIV}",
                            "shortIds": [ "${XRAY_SID}" ]
                        }
                    },
                    "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "routeOnly": true }
                }
            ],
            "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
        }
        EOF_XRAY_CONFIG
          # The client link needs the PUBLIC key + shortId, which are not in the
          # server config — persist the ready vless:// link for the report.
          printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#gryonixNexus\n' \
            "$XRAY_UUID" "\#(host)" "\#(port)" "\#(sni)" "$XRAY_PUB" "$XRAY_SID" > link.txt
        fi
        chmod 600 config/config.json link.txt
        docker compose -p \#(Self.composeProject) pull -q
        docker compose -p \#(Self.composeProject) up -d
        """#]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(context.settings.xrayRealityPort, .tcp, comment: "VLESS/Reality")]
    }

    /// Not an HTTP service — no reverse proxy
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.xrayRealityPath
        let port = context.settings.xrayRealityPort
        let lang = context.language
        let endpoint = "\(hostname(context)):\(port)"
        return [#"""
        echo "VLESS/Reality: \#(endpoint) (TCP)"
        echo "  \#(L10nServices.xrayLinkLabel(lang)):"
        echo "  $(cat \#(path)/link.txt)"
        echo "  \#(L10nServices.xrayClientsNote(lang))"
        echo "  \#(L10nServices.adminViaWireGuardNote(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        return ServiceActions(
            statusProbe: .container(
                name: Self.containerName,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.containerName, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.containerName, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.containerName, "stop", timeoutClass: .restart),
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image])
    }
}
