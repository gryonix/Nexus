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
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

/** OpenVPN — the classic UDP VPN, for maximum client compatibility */
class OpenVPNService : ManagedService {
    override val id = ServiceID.OPEN_VPN
    override val displayName = "OpenVPN"
    override val systemImage = "lock.shield"
    override val category = ServiceCategory.VPN
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.vpnHostname
        return if (custom.isEmpty()) "vpn.${context.domain}" else custom
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.openVPNPath
        val port = context.settings.openVPNPort
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              openvpn:
                image: $IMAGE
                container_name: $CONTAINER_NAME
                restart: unless-stopped
                cap_add:
                  - NET_ADMIN
                devices:
                  - /dev/net/tun
                sysctls:
                  - net.ipv4.ip_forward=1
                volumes:
                  - $path/data:/etc/openvpn
                ports:
                  - "$port:1194/udp"
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.openVPNPath
        val port = context.settings.openVPNPort
        val host = hostname(context)
        val lang = context.language

        val dockerfile = """
        FROM $BASE_IMAGE
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
        """.trimIndent()

        val runScript = """
        #!/bin/sh
        set -eu
        mkdir -p /dev/net
        [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200
        iptables -t nat -C POSTROUTING -s $SUBNET/24 -j MASQUERADE 2>/dev/null || \
          iptables -t nat -A POSTROUTING -s $SUBNET/24 -j MASQUERADE
        exec openvpn --config /etc/openvpn/server.conf
        """.trimIndent()

        val getClientScript = """
        #!/bin/sh
        set -eu
        CN="${SH}1"
        PKI=/etc/openvpn/pki
        . /etc/openvpn/gryonix-env
        cat <<PROFILE
        client
        dev tun
        proto udp
        remote ${SH}OVPN_HOST ${SH}OVPN_PORT
        resolv-retry infinite
        nobind
        persist-key
        persist-tun
        remote-cert-tls server
        verb 3
        <ca>
        ${SH}(cat "${SH}PKI/ca.crt")
        </ca>
        <cert>
        ${SH}(openssl x509 -in "${SH}PKI/issued/${SH}CN.crt")
        </cert>
        <key>
        ${SH}(cat "${SH}PKI/private/${SH}CN.key")
        </key>
        <tls-crypt>
        ${SH}(cat /etc/openvpn/tc.key)
        </tls-crypt>
        PROFILE
        """.trimIndent()

        val revokeClientScript = """
        #!/bin/sh
        set -eu
        CN="${SH}1"
        PKI=/etc/openvpn/pki
        easyrsa revoke "${SH}CN"
        easyrsa gen-crl
        cp -f "${SH}PKI/crl.pem" /etc/openvpn/crl.pem
        chmod 644 /etc/openvpn/crl.pem
        if [ "${SH}{2:-}" = "remove" ]; then
          rm -f "${SH}PKI/issued/${SH}CN.crt" "${SH}PKI/private/${SH}CN.key" "${SH}PKI/reqs/${SH}CN.req"
        fi
        """.trimIndent()

        val serverConf = """
        # Managed by gryonixNexus — OpenVPN server (container-internal port 1194).
        server $SUBNET 255.255.255.0
        topology subnet
        port 1194
        proto udp
        dev tun
        ca /etc/openvpn/pki/ca.crt
        cert /etc/openvpn/pki/issued/$host.crt
        key /etc/openvpn/pki/private/$host.key
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
        """.trimIndent()

        return listOf("""
        log "OpenVPN: ${L10nServices.serviceStarting(lang)}"
        install -d $path/data $path/build
        cat > $path/build/Dockerfile <<'EOF_OVPN_DOCKERFILE'
        @DOCKERFILE@
        EOF_OVPN_DOCKERFILE
        cat > $path/build/gryonix-ovpn-run <<'EOF_OVPN_RUN'
        @RUN@
        EOF_OVPN_RUN
        cat > $path/build/ovpn_getclient <<'EOF_OVPN_GETCLIENT'
        @GETCLIENT@
        EOF_OVPN_GETCLIENT
        cat > $path/build/ovpn_revokeclient <<'EOF_OVPN_REVOKE'
        @REVOKE@
        EOF_OVPN_REVOKE
        cd $path
        docker build -q -t $IMAGE build >/dev/null
        # First run only: build the EC PKI, the tls-crypt key, the server
        # config and the initial client profile; re-runs keep all of it.
        if [ ! -f data/pki/ca.crt ]; then
          docker run --rm -v $path/data:/etc/openvpn $IMAGE sh -c "
            set -eu
            easyrsa init-pki
            easyrsa build-ca nopass
            easyrsa --san=DNS:$host build-server-full $host nopass
            easyrsa build-client-full $CLIENT_NAME nopass
            easyrsa gen-crl
            cp -f /etc/openvpn/pki/crl.pem /etc/openvpn/crl.pem
            chmod 644 /etc/openvpn/crl.pem
            openvpn --genkey secret /etc/openvpn/tc.key
          "
          printf 'OVPN_HOST=%s\nOVPN_PORT=%s\n' '$host' '$port' > data/gryonix-env
          cat > data/server.conf <<'EOF_OVPN_SERVER'
        @SERVERCONF@
        EOF_OVPN_SERVER
          docker run --rm -v $path/data:/etc/openvpn $IMAGE \
            ovpn_getclient $CLIENT_NAME > $path/$CLIENT_NAME.ovpn
        fi
        chmod 640 $path/$CLIENT_NAME.ovpn
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent().embedding(
            "DOCKERFILE" to dockerfile,
            "RUN" to runScript,
            "GETCLIENT" to getClientScript,
            "REVOKE" to revokeClientScript,
            "SERVERCONF" to serverConf
        ))
    }

    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(context.settings.openVPNPort, FirewallPort.Proto.UDP, comment = "OpenVPN")
    )

    /** Not an HTTP service — no reverse proxy */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.openVPNPath
        val port = context.settings.openVPNPort
        val lang = context.language
        val endpoint = "${hostname(context)}:$port"
        return listOf("""
        echo "OpenVPN: $endpoint (UDP)"
        echo "  ${L10nServices.openVPNConfigLabel(lang)}:"
        echo "  ----- BEGIN $CLIENT_NAME.ovpn -----"
        cat $path/$CLIENT_NAME.ovpn
        echo "  ----- END $CLIENT_NAME.ovpn -----"
        echo "  ${L10nServices.openVPNClientsNote(lang)}"
        echo "  ${L10nServices.adminViaWireGuardNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.Container(
            name = CONTAINER_NAME,
            list = PrivilegedCommand("/usr/bin/docker", "ps -a")
        ),
        restart = ServicePower.container(CONTAINER_NAME, "restart"),
        start = ServicePower.container(CONTAINER_NAME, "start"),
        stop = ServicePower.container(CONTAINER_NAME, "stop")
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec.builtOnServer(listOf(IMAGE))

    companion object {
        const val COMPOSE_PROJECT = "openvpn"
        const val CONTAINER_NAME = "openvpn"

        const val IMAGE = "gryonix-openvpn:local"

        /** Pinned multi-arch base (amd64/arm64/armv7/…) the local build starts from */
        const val BASE_IMAGE = "alpine:3.22"

        /** Client certificate common name baked into client.ovpn */
        const val CLIENT_NAME = "gryonixnexus"

        const val SUBNET = "10.11.0.0"
    }
}
