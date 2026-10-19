package com.skaymer.gryonixnexus.catalog

/** AmneziaWG on the WireGuard port; first bytes pick the server */
object VPNPortShare {
    /** The drop-in the ruleset includes */
    const val PATH = "/etc/nftables.d/gryonixnexus-svc-vpn-share.nft"

    /** The table the drop-in owns */
    const val TABLE = "inet gryonixnexus_vpn_share"

    /** The port AmneziaWG shares, when WireGuard runs beside it */
    fun sharedPort(context: ServiceContext): Int? {
        val settings = context.settings
        val both = ServiceID.WIREGUARD_VPN in context.installedServices &&
            ServiceID.AMNEZIA_WG in context.installedServices
        return if (both && settings.wireguardVPNPort != settings.amneziaWGPort) settings.wireguardVPNPort else null
    }

    /** The port AmneziaWG clients connect to */
    fun clientPort(context: ServiceContext): Int = sharedPort(context) ?: context.settings.amneziaWGPort

    /** WireGuard's own packets stay; every other flow moves to AmneziaWG */
    fun dropIn(wireGuardPort: Int, amneziaPort: Int): String = """
        # Managed by gryonixNexus: AmneziaWG answers on the WireGuard port.
        # WireGuard packets start with type 1-4 and three zeros.
        table $TABLE
        delete table $TABLE
        table $TABLE {
            chain prerouting {
                type nat hook prerouting priority dstnat - 10; policy accept;
                udp dport $wireGuardPort @th,64,32 != { 0x01000000, 0x02000000, 0x03000000, 0x04000000 } redirect to :$amneziaPort
            }
        }
        """.trimIndent() + "\n"

    /** Writes and applies the drop-in, or removes its table */
    fun section(context: ServiceContext): String {
        val port = sharedPort(context)
            ?: return "rm -f $PATH\nnft delete table $TABLE 2>/dev/null || true"
        return "install -d -m 755 /etc/nftables.d\n" +
            "cat > $PATH <<'EOF_VPN_SHARE'\n" +
            dropIn(port, context.settings.amneziaWGPort) +
            "EOF_VPN_SHARE\nnft -f $PATH"
    }
}
