import gryonixNexusCore

/// Contents of /etc/wireguard/wg0.conf for both sides — scenario B only
enum WireGuardConfig {
    static func vpsConf(
        context: MailContext,
        vpsKeys: WireGuardKeyPair,
        homePublicKey: String
    ) -> String? {
        guard let vps = context.server(.vpsRelay),
              let home = context.server(.homeBackend),
              case .ipv4(let vpsWG)? = vps.vpnAddress,
              case .ipv4(let homeWG)? = home.vpnAddress else {
            return nil
        }
        return """
        # Managed by gryonixNexus — WireGuard on the VPS (tunnel server).
        # This file contains a private key: mode 600, never publish it.
        [Interface]
        Address = \(vpsWG)/24
        ListenPort = \(WireGuardDefaults.listenPort)
        PrivateKey = \(vpsKeys.privateKey)

        [Peer]
        # Home mail server (behind NAT)
        PublicKey = \(homePublicKey)
        AllowedIPs = \(homeWG)/32
        """
    }

    static func homeConf(
        context: MailContext,
        homeKeys: WireGuardKeyPair,
        vpsPublicKey: String
    ) -> String? {
        guard let vps = context.server(.vpsRelay),
              let home = context.server(.homeBackend),
              case .ipv4(let homeWG)? = home.vpnAddress,
              let endpoint = vps.publicAddress else {
            return nil
        }
        return """
        # Managed by gryonixNexus — WireGuard on the home server (tunnel client).
        # This file contains a private key: mode 600, never publish it.
        [Interface]
        Address = \(homeWG)/24
        PrivateKey = \(homeKeys.privateKey)

        [Peer]
        # VPS — the public entry point
        PublicKey = \(vpsPublicKey)
        Endpoint = \(endpoint.value):\(WireGuardDefaults.listenPort)
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
        """
    }
}
