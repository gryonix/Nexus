package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.core.WireGuardDefaults

/** Contents of /etc/wireguard/wg0.conf for both sides — scenario B only */
internal object WireGuardConfig {
    fun vpsConf(context: MailContext, vpsKeys: WireGuardKeyPair,
                homePublicKey: String): String? {
        val vps = context.server(ServerRole.VPS_RELAY) ?: return null
        val home = context.server(ServerRole.HOME_BACKEND) ?: return null
        val vpsWG = vps.vpnAddress as? NetworkAddress.IPv4 ?: return null
        val homeWG = home.vpnAddress as? NetworkAddress.IPv4 ?: return null
        return """
        # Managed by gryonixNexus — WireGuard on the VPS (tunnel server).
        # This file contains a private key: mode 600, never publish it.
        [Interface]
        Address = ${vpsWG.value}/24
        ListenPort = ${WireGuardDefaults.LISTEN_PORT}
        PrivateKey = ${vpsKeys.privateKey}

        [Peer]
        # Home mail server (behind NAT)
        PublicKey = $homePublicKey
        AllowedIPs = ${homeWG.value}/32
        """.trimIndent()
    }

    fun homeConf(context: MailContext, homeKeys: WireGuardKeyPair,
                 vpsPublicKey: String): String? {
        val vps = context.server(ServerRole.VPS_RELAY) ?: return null
        val home = context.server(ServerRole.HOME_BACKEND) ?: return null
        val homeWG = home.vpnAddress as? NetworkAddress.IPv4 ?: return null
        val endpoint = vps.publicAddress ?: return null
        return """
        # Managed by gryonixNexus — WireGuard on the home server (tunnel client).
        # This file contains a private key: mode 600, never publish it.
        [Interface]
        Address = ${homeWG.value}/24
        PrivateKey = ${homeKeys.privateKey}

        [Peer]
        # VPS — the public entry point
        PublicKey = $vpsPublicKey
        Endpoint = ${endpoint.value}:${WireGuardDefaults.LISTEN_PORT}
        # Full tunnel: all outbound traffic goes via the VPS so that mail
        # leaves from the VPS IP (matching PTR/SPF). wg-quick sets up the
        # routes — in its OWN table, which is also what keeps them out of
        # docker's way: a split list written here instead lands 32 prefixes in
        # the MAIN table, and docker then refuses to allocate any bridge subnet
        # at all.
        #
        # What a default route costs is the exemption for the tunnel's OWN
        # packets, which wg-quick makes with `fwmark 51820` and which any
        # other mangle rule on the host can clear — mailcow's netfilter
        # container sets a mark on every outgoing packet, and mailcow is a
        # service from this same catalogue. The encrypted UDP then matches the
        # default route wg-quick just installed, is encrypted again, and the
        # machine sends hundreds of megabytes a second to itself with no
        # internet at all. Same live run, same afternoon.
        #
        # So the relay's own address is pinned in the main table by
        # `gryonixnexus-tunnel-endpoint.service`, before this interface comes
        # up. A unit and not a `PreUp` here: a failing hook takes the whole
        # interface down with it, and Ubuntu 26.04 confines wg-quick with an
        # AppArmor profile allowing only `ip`, `nft` and `sysctl` — a hook
        # needing a shell pipeline is denied, silently, under `|| true`.
        AllowedIPs = 0.0.0.0/0
        PersistentKeepalive = 25
        """.trimIndent()
    }
}
