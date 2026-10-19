import gryonixNexusCore
import ServiceCatalog

/// nftables rulesets (default-deny) — embedded into setup scripts via heredoc
enum NftablesConfig {
    static let publicInterfacePlaceholder = "@PUB_IF@"

    private static let noForwardChain = """
            # No forward chain: Docker hooks its own drop-policy forward
            # chain with per-container accepts; a second drop-policy
            # chain here would override it and cut containers off.
        """

    private static func udpAcceptSuffix(_ udpPorts: [Int], prefix: String = "") -> String {
        guard !udpPorts.isEmpty else { return "" }
        let ports = udpPorts.map(String.init).joined(separator: ", ")
        return "\n        \(prefix)udp dport { \(ports) } accept comment \"VPN clients\""
    }

    private static func sshThrottle(port: Int) -> String {
        """
                tcp dport \(port) meter gryonixnexus_ssh_throttle4 { ip saddr timeout 60s limit rate 10/minute burst 5 packets } accept comment "SSH, per-source throttle"
                tcp dport \(port) meter gryonixnexus_ssh_throttle6 { ip6 saddr timeout 60s limit rate 10/minute burst 5 packets } accept comment "SSH, per-source throttle"
                tcp dport \(port) drop comment "SSH: per-source rate exceeded"
        """
    }

    /// Multicast only: never routed, so never from the internet
    static let homeDiscoveryRules = """
                ip daddr { 224.0.0.251, 239.255.255.250 } udp dport { 5353, 1900 } accept comment "home devices discovery"
                ip6 daddr { ff02::fb, ff02::c } udp dport { 5353, 1900 } accept comment "home devices discovery"
        """

    private static func homeDiscovery(_ context: MailContext) -> String {
        let wanted = ServiceRegistry.services(context.input.services).contains(where: \.requiresHomeMachine)
        return wanted ? "\n" + homeDiscoveryRules : ""
    }

    static let agentChainName = "gryonixnexus_services"
    static let agentDropInDirectory = "/etc/nftables.d"
    static let agentDropInInclude = "include \"/etc/nftables.d/gryonixnexus-*.nft\""

    private static let agentChain = """

            # Filled by the control-plane agent when it installs a service that
            # needs a port open (`flush chain` + `add rule`, never a reload of
            # this file). Empty means nothing extra is open.
            chain \(agentChainName) {
            }
    """

    static func singleHostRuleset(_ context: MailContext) -> String {
        let sshPort = context.security.ssh.port
        let ports = context.forwardedPorts.map(String.init).joined(separator: ", ")
        return """
        #!/usr/sbin/nft -f
        # Managed by gryonixNexus — single-server firewall (default-deny).
        flush ruleset

        table inet filter {
            chain input {
                type filter hook input priority filter; policy drop;
                iif "lo" accept
                ct state established,related accept
                ct state invalid drop
                meta l4proto icmp icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } limit rate 10/second accept
                meta l4proto ipv6-icmp accept
        \(sshThrottle(port: sshPort))
                tcp dport { \(ports) } accept comment "mail + HTTP for ACME"\(udpAcceptSuffix(context.forwardedUDPPorts))\(homeDiscovery(context))
                jump \(agentChainName)
            }
        \(agentChain)\(noForwardChain)
        }

        \(agentDropInInclude)
        """
    }

    static func homeRuleset(_ context: MailContext) -> String {
        let sshPort = context.security.ssh.port
        let ports = context.forwardedPorts.map(String.init).joined(separator: ", ")
        let wgIF = WireGuardDefaults.interfaceName
        return """
        #!/usr/sbin/nft -f
        # Managed by gryonixNexus — home-server firewall (default-deny).
        # Mail ports are reachable ONLY from the WireGuard tunnel (from the VPS).
        flush ruleset

        table inet filter {
            chain input {
                type filter hook input priority filter; policy drop;
                iif "lo" accept
                ct state established,related accept
                ct state invalid drop
                meta l4proto icmp icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } limit rate 10/second accept
                meta l4proto ipv6-icmp accept
                # SSH: throttled per source below rather than flatly accepted
                # (a flood that never fails an auth never gets a CrowdSec
                # ban — see `sshThrottle`). To narrow it to your LAN instead:
                # ip saddr 192.168.1.0/24 tcp dport \(sshPort) accept
        \(sshThrottle(port: sshPort))
                iifname "\(wgIF)" tcp dport { \(ports) } accept comment "mail from the tunnel"\(udpAcceptSuffix(context.forwardedUDPPorts, prefix: "iifname \"\(wgIF)\" "))\(homeDiscovery(context))
                jump \(agentChainName)
            }

            chain prerouting {
                type filter hook prerouting priority mangle; policy accept;
                # New connections arriving from the relay get a mark so their
                # replies route back through the tunnel instead of the home
                # ISP's default gateway — real public client IPs are outside
                # 10.8.0.0/24, so nothing routes them back here automatically.
                ct state new iifname "\(wgIF)" ct mark set 0x1
                \(outboundMailMark)\(relaySitesMark(context))
                # Restore the mark onto every packet of an already-marked
                # connection (both directions) so the policy-routing table below
                # actually sees it — ct mark alone is invisible to `ip rule`.
                meta mark set ct mark
            }

            # Every relayed service on this host terminates at a LOCAL
            # process (Caddy binds the host's own address directly; mail
            # engines the same) — its replies are OUTPUT packets, never
            # forwarded ones, so `chain prerouting` above never sees them.
            # Without this chain, a relayed HTTPS
            # request's SYN arrived correctly (marked, DNAT-preserved real
            # client IP and all), but Caddy's SYN-ACK carried no mark, fell
            # through to the main routing table, and never found its way
            # back through the tunnel — the connection just hung. `type
            # route hook output` is nftables' own mechanism for exactly
            # this: changing a locally-generated packet's mark and having
            # the kernel redo the route lookup that already happened.
            chain output {
                type route hook output priority mangle; policy accept;
                \(outboundMailMark)\(relaySitesMark(context))
                meta mark set ct mark
            }

            # The mark reroutes a host process after it picked its
            # source; the tunnel takes only its own address.
            chain postrouting {
                type nat hook postrouting priority srcnat; policy accept;
                oifname "\(wgIF)" meta mark 0x1 masquerade
            }
        \(agentChain)\(noForwardChain)
        }

        \(agentDropInInclude)
        """
    }

    private static let outboundMailMark = """
        # Outbound SMTP goes through the relay so it leaves from the address
                # SPF authorises and PTR names; `!= local` keeps mail ARRIVING
                # for this host out of it.
                ct state new tcp dport 25 fib daddr type != local ct mark set 0x1
        """

    /// Sends traffic for the relay's sites through the tunnel
    private static func relaySitesMark(_ context: MailContext) -> String {
        guard let vpsPublicIP = context.server(.vpsRelay)?.publicAddress?.value,
              !context.forwardedPorts.isEmpty else { return "" }
        let ports = context.forwardedPorts.map(String.init).joined(separator: ", ")
        return """

                # The relay's own sites go through the tunnel, so VPN clients
                # reach them as the relay's hairpin address.
                ct state new ip daddr \(vpsPublicIP) tcp dport { \(ports) } ct mark set 0x1
        """
    }

    static func vpsRuleset(_ context: MailContext) -> String? {
        guard let home = context.server(.homeBackend),
              case .ipv4(let homeWG)? = home.vpnAddress,
              let vpsPublicIP = context.server(.vpsRelay)?.publicAddress?.value,
              let subnet = context.wireGuardSubnet else {
            return nil
        }
        let sshPort = context.security.ssh.port
        let wgPort = WireGuardDefaults.listenPort
        let wgIF = WireGuardDefaults.interfaceName
        let ports = context.forwardedPorts.map(String.init).joined(separator: ", ")
        let udpPorts = context.forwardedUDPPorts.map(String.init).joined(separator: ", ")
        let udpForward = udpPorts.isEmpty ? ""
            : "\n        iifname $pub_if oifname \"\(wgIF)\" ip daddr $home_ip udp dport { \(udpPorts) } accept"
        let udpDNAT = udpPorts.isEmpty ? ""
            : "\n        iifname $pub_if udp dport { \(udpPorts) } dnat to $home_ip"
        let udpHairpinDNAT = udpPorts.isEmpty ? ""
            : "\n        iifname \"\(wgIF)\" ip daddr $vps_public udp dport { \(udpPorts) } dnat to $home_ip"
        let udpHairpinForward = udpPorts.isEmpty ? ""
            : "\n        iifname \"\(wgIF)\" oifname \"\(wgIF)\" ip daddr $home_ip udp dport { \(udpPorts) } accept"
        let hairpinSrc = homeWG.split(separator: ".").dropLast().map(String.init).joined(separator: ".") + ".254"
        return """
        #!/usr/sbin/nft -f
        # Managed by gryonixNexus — VPS relay: firewall + DNAT of mail ports into the tunnel.
        # The public interface is detected automatically by the setup script.
        define pub_if = "\(publicInterfacePlaceholder)"
        define home_ip = \(homeWG)
        define vps_public = \(vpsPublicIP)
        # Distinct SNAT source for hairpinned VPN-client traffic (see
        # postrouting): kept apart from the relay masquerade so the home
        # admin guard can allow VPN clients while blocking public visitors.
        define hairpin_src = \(hairpinSrc)

        flush ruleset

        table inet filter {
            chain input {
                type filter hook input priority filter; policy drop;
                iif "lo" accept
                ct state established,related accept
                ct state invalid drop
                meta l4proto icmp icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } limit rate 10/second accept
                meta l4proto ipv6-icmp accept
        \(sshThrottle(port: sshPort))
                udp dport \(wgPort) accept comment "WireGuard"
                # Mail ports are NOT accepted on input: the traffic is
                # DNATed and passes only through the forward chain.
                jump \(agentChainName)
            }

            # MSS clamping, and it is not an optimisation — without it a
            # relayed HTTPS connection completes its TCP handshake and then
            # HANGS. The client's TLS ClientHello arrived at
            # sequence 1449 with the first 1448 bytes missing, and the home node
            # answered with a SACK naming the hole. A public client sizes its
            # segments for ITS OWN path (mss 1460) and knows nothing about a
            # 1420-byte tunnel in the middle, so every full-size segment falls
            # into an MTU black hole. Nothing earlier caught it because
            # everything tested through this relay until then was small: an
            # ACME challenge, an SMTP handshake, a short message.
            #
            # Both directions, because both ends size their own segments: the
            # client's SYN is clamped on its way OUT through the tunnel, and the
            # home node's SYN-ACK on its way in. `rt mtu` is the route's own MTU,
            # so the number is never hardcoded.
            #
            # Its own chain at mangle priority: the filter chain below runs at
            # `filter` priority and its accept/drop verdicts would end traversal
            # before an option rewrite could happen.
            chain mangle_forward {
                type filter hook forward priority mangle; policy accept;
                oifname "\(wgIF)" tcp flags syn tcp option maxseg size set rt mtu
                iifname "\(wgIF)" tcp flags syn tcp option maxseg size set rt mtu
            }

            chain forward {
                # policy ACCEPT, and every drop below names an interface.
                # nftables hands the packet to EVERY chain hooked at forward
                # and one drop verdict anywhere is final, so a drop policy
                # here also vetoes the per-container accepts Docker keeps in
                # its own tables: containers on this host lose the network
                # entirely (no pulls, no outbound) while the host itself is
                # fine — it reads as "Docker is broken", not as "the firewall
                # did this". The other rulesets solve that by declaring no
                # forward chain at all; the relay cannot, its forward rules
                # ARE the relay. So the default is inverted instead and
                # default-deny is spelled out for the paths this host routes:
                # anything touching the tunnel, and routing between public
                # interfaces. Traffic we do not own falls through to whoever
                # else is hooked here — on a Docker host, Docker's own chain.
                type filter hook forward priority filter; policy accept;
                iifname "\(wgIF)" ct state invalid drop
                oifname "\(wgIF)" ct state invalid drop
                ct state established,related accept
                # Inbound mail/HTTP DNATed to the home node.
                iifname $pub_if oifname "\(wgIF)" ip daddr $home_ip tcp dport { \(ports) } accept\(udpForward)
                # Hairpinned tunnel traffic to the deployment's own sites —
                # DNATed back into the tunnel, so both interfaces are \(wgIF).
                iifname "\(wgIF)" oifname "\(wgIF)" ip daddr $home_ip tcp dport { \(ports) } accept\(udpHairpinForward)
                # Traffic initiated by the home node (outgoing mail,
                # updates in full-tunnel mode) — out through the VPS.
                iifname "\(wgIF)" oifname $pub_if accept
                # The default-deny the policy used to provide, restated for
                # the two paths that need it: nothing else enters or leaves
                # the tunnel, and the relay is not an open router between
                # public interfaces. Docker's bridges are named in neither,
                # which is exactly the point — no interface list to go stale.
                iifname "\(wgIF)" drop
                oifname "\(wgIF)" drop
                iifname $pub_if oifname $pub_if drop
            }
        \(agentChain)
        }

        table ip nat {
            chain prerouting {
                type nat hook prerouting priority dstnat;
                iifname $pub_if tcp dport { \(ports) } dnat to $home_ip\(udpDNAT)
                iifname "\(wgIF)" ip daddr $vps_public tcp dport { \(ports) } dnat to $home_ip\(udpHairpinDNAT)
            }
            chain output {
                type nat hook output priority dstnat;
                # This relay reaching its own forwarded sites
                ip daddr $vps_public tcp dport { \(ports) } dnat to $home_ip
            }
            chain postrouting {
                type nat hook postrouting priority srcnat;
                # Hairpin VPN-client flows (in on \(wgIF), DNATed back out
                # \(wgIF)) get a DISTINCT source so the home admin guard can
                # tell them apart from relayed PUBLIC traffic. Both otherwise
                # masquerade to the same VPS tunnel address, and the guard —
                # which sees only the L3 source — could not distinguish a VPN
                # client from a public visitor, so "VPN-only" blocked everyone.
                # First matching NAT wins, so this precedes the masquerade.
                iifname "\(wgIF)" oifname "\(wgIF)" ip daddr $home_ip snat to $hairpin_src
                # Relayed public traffic is deliberately left un-NATed here:
                # DNAT alone survives the round trip (conntrack un-DNATs the
                # reply automatically on its way back out $pub_if), so the
                # real client IP rides all the way to home instead of being
                # collapsed into this relay's tunnel address. See homeRuleset
                # and RelayRouteSyncSections for the other half — home has to
                # route the reply back through the tunnel itself, since a
                # foreign public source address is not something its main
                # routing table sends to wg0 by default.
                # Tunnel traffic egressing to the internet: mail leaves
                # from the VPS public IP (matching PTR/SPF).
                oifname $pub_if ip saddr \(subnet) masquerade
                oifname "\(wgIF)" ip saddr $vps_public masquerade
            }
        }

        \(agentDropInInclude)
        """
    }

    static let vpsSysctl = """
    # Managed by gryonixNexus — forwarding is mandatory: the VPS DNATs traffic into the tunnel.
    net.ipv4.ip_forward = 1
    # Loose rp_filter: strict mode may drop tunnel traffic.
    net.ipv4.conf.all.rp_filter = 2
    net.ipv4.conf.default.rp_filter = 2
    """

    static let homeSysctl = """
    # Managed by gryonixNexus — loose rp_filter: relayed traffic arrives with a
    # foreign source IP (the real public visitor, not a tunnel peer), which
    # strict reverse-path filtering would otherwise drop as spoofed.
    net.ipv4.conf.all.rp_filter = 2
    net.ipv4.conf.default.rp_filter = 2
    """
}
