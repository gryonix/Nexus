public struct OpenVPNService: ManagedService {
    public static let composeProject = "openvpn"
    public static let containerName = "openvpn"
    public static let image = "gryonix-openvpn:local"
    /// Pinned multi-arch base (amd64/arm64/armv7/…) the local build starts from
    public static let baseImage = "alpine:3.22"
    /// Client certificate common name baked into client.ovpn
    public static let clientName = "gryonixnexus"
    public static let subnet = "10.11.0.0"

    public let id = ServiceID.openVPN
    public let displayName = "OpenVPN"
    public let systemImage = "lock.shield"
    public let category = ServiceCategory.vpn
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.vpnHostname
        return custom.isEmpty ? "vpn.\(context.domain)" : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.openVPNPath
        let port = context.settings.openVPNPort
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              openvpn:
                image: \(Self.image)
                container_name: \(Self.containerName)
                restart: unless-stopped
                cap_add:
                  - NET_ADMIN
                devices:
                  - /dev/net/tun
                sysctls:
                  - net.ipv4.ip_forward=1
                volumes:
                  - \(path)/data:/etc/openvpn
                ports:
                  - "\(port):1194/udp"
            """,
            envTemplate: nil
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.openVPNPath
        let port = context.settings.openVPNPort
        let host = hostname(context)
        let lang = context.language
        let dockerfile = #"""
        FROM \#(Self.baseImage)
        RUN apk add --no-cache openvpn easy-rsa iptables openssl
        ENV OPENVPN=/etc/openvpn \
            EASYRSA=/usr/share/easy-rsa \
            EASYRSA_PKI=/etc/openvpn/pki \
            EASYRSA_ALGO=ec \
            EASYRSA_CURVE=prime256v1 \
            EASYRSA_CRL_DAYS=3650 \
            EASYRSA_BATCH=1
        RUN ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin/easyrsa
        COPY ovpn_getclient ovpn_revokeclient gryonix-ovpn-run /usr/local/bin/
        RUN chmod +x /usr/local/bin/ovpn_getclient /usr/local/bin/ovpn_revokeclient /usr/local/bin/gryonix-ovpn-run
        CMD ["gryonix-ovpn-run"]
        """#
        let runScript = #"""
        #!/bin/sh
        set -eu
        mkdir -p /dev/net
        [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200
        iptables -t nat -C POSTROUTING -s \#(Self.subnet)/24 -j MASQUERADE 2>/dev/null || \
          iptables -t nat -A POSTROUTING -s \#(Self.subnet)/24 -j MASQUERADE
        exec openvpn --config /etc/openvpn/server.conf
        """#
        let getClientScript = #"""
        #!/bin/sh
        set -eu
        CN="$1"
        PKI=/etc/openvpn/pki
        . /etc/openvpn/gryonix-env
        cat <<PROFILE
        client
        dev tun
        proto udp
        remote $OVPN_HOST $OVPN_PORT
        resolv-retry infinite
        nobind
        persist-key
        persist-tun
        remote-cert-tls server
        verb 3
        <ca>
        $(cat "$PKI/ca.crt")
        </ca>
        <cert>
        $(openssl x509 -in "$PKI/issued/$CN.crt")
        </cert>
        <key>
        $(cat "$PKI/private/$CN.key")
        </key>
        <tls-crypt>
        $(cat /etc/openvpn/tc.key)
        </tls-crypt>
        PROFILE
        """#
        let revokeClientScript = #"""
        #!/bin/sh
        set -eu
        CN="$1"
        PKI=/etc/openvpn/pki
        easyrsa revoke "$CN"
        easyrsa gen-crl
        cp -f "$PKI/crl.pem" /etc/openvpn/crl.pem
        chmod 644 /etc/openvpn/crl.pem
        if [ "${2:-}" = "remove" ]; then
          rm -f "$PKI/issued/$CN.crt" "$PKI/private/$CN.key" "$PKI/reqs/$CN.req"
        fi
        """#
        let serverConf = #"""
        # Managed by gryonixNexus — OpenVPN server (container-internal port 1194).
        server \#(Self.subnet) 255.255.255.0
        topology subnet
        port 1194
        proto udp
        dev tun
        ca /etc/openvpn/pki/ca.crt
        cert /etc/openvpn/pki/issued/\#(host).crt
        key /etc/openvpn/pki/private/\#(host).key
        dh none
        ecdh-curve prime256v1
        tls-crypt /etc/openvpn/tc.key
        crl-verify /etc/openvpn/crl.pem
        keepalive 10 60
        persist-key
        persist-tun
        user nobody
        group nobody
        push "redirect-gateway def1"
        push "block-ipv6"
        push "dhcp-option DNS 1.1.1.1"
        push "dhcp-option DNS 1.0.0.1"
        explicit-exit-notify 1
        verb 3
        """#
        return [#"""
        log "OpenVPN: \#(L10nServices.serviceStarting(lang))"
        install -d \#(path)/data \#(path)/build
        cat > \#(path)/build/Dockerfile <<'EOF_OVPN_DOCKERFILE'
        \#(dockerfile)
        EOF_OVPN_DOCKERFILE
        cat > \#(path)/build/gryonix-ovpn-run <<'EOF_OVPN_RUN'
        \#(runScript)
        EOF_OVPN_RUN
        cat > \#(path)/build/ovpn_getclient <<'EOF_OVPN_GETCLIENT'
        \#(getClientScript)
        EOF_OVPN_GETCLIENT
        cat > \#(path)/build/ovpn_revokeclient <<'EOF_OVPN_REVOKE'
        \#(revokeClientScript)
        EOF_OVPN_REVOKE
        cd \#(path)
        docker build -q -t \#(Self.image) build >/dev/null
        # First run only: build the EC PKI, the tls-crypt key, the server
        # config and the initial client profile; re-runs keep all of it.
        if [ ! -f data/pki/ca.crt ]; then
          docker run --rm -v \#(path)/data:/etc/openvpn \#(Self.image) sh -c "
            set -eu
            easyrsa init-pki
            easyrsa build-ca nopass
            easyrsa --san=DNS:\#(host) build-server-full \#(host) nopass
            easyrsa build-client-full \#(Self.clientName) nopass
            easyrsa gen-crl
            cp -f /etc/openvpn/pki/crl.pem /etc/openvpn/crl.pem
            chmod 644 /etc/openvpn/crl.pem
            openvpn --genkey secret /etc/openvpn/tc.key
          "
          printf 'OVPN_HOST=%s\nOVPN_PORT=%s\n' '\#(host)' '\#(port)' > data/gryonix-env
          cat > data/server.conf <<'EOF_OVPN_SERVER'
        \#(serverConf)
        EOF_OVPN_SERVER
          docker run --rm -v \#(path)/data:/etc/openvpn \#(Self.image) \
            ovpn_getclient \#(Self.clientName) > \#(path)/\#(Self.clientName).ovpn
        fi
        chmod 640 \#(path)/\#(Self.clientName).ovpn
        docker compose -p \#(Self.composeProject) up -d
        """#]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(context.settings.openVPNPort, .udp, comment: "OpenVPN")]
    }

    /// Not an HTTP service — no reverse proxy
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.openVPNPath
        let port = context.settings.openVPNPort
        let lang = context.language
        let endpoint = "\(hostname(context)):\(port)"
        return [#"""
        echo "OpenVPN: \#(endpoint) (UDP)"
        echo "  \#(L10nServices.openVPNConfigLabel(lang)):"
        echo "  ----- BEGIN \#(Self.clientName).ovpn -----"
        cat \#(path)/\#(Self.clientName).ovpn
        echo "  ----- END \#(Self.clientName).ovpn -----"
        echo "  \#(L10nServices.openVPNClientsNote(lang))"
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
        .builtOnServer([Self.image])
    }
}
