/// AmneziaWG on the WireGuard port; first bytes pick the server
public enum VPNPortShare {
    /// The drop-in the ruleset includes
    public static let path = "/etc/nftables.d/gryonixnexus-svc-vpn-share.nft"
    /// The table the drop-in owns
    public static let table = "inet gryonixnexus_vpn_share"

    /// The port AmneziaWG shares, when WireGuard runs beside it
    public static func sharedPort(_ context: ServiceContext) -> Int? {
        let settings = context.settings
        guard context.installedServices.contains(.wireguardVPN),
              context.installedServices.contains(.amneziaWG),
              settings.wireguardVPNPort != settings.amneziaWGPort else { return nil }
        return settings.wireguardVPNPort
    }

    /// The port AmneziaWG clients connect to
    public static func clientPort(_ context: ServiceContext) -> Int {
        sharedPort(context) ?? context.settings.amneziaWGPort
    }

    /// WireGuard's own packets stay; every other flow moves to AmneziaWG
    public static func dropIn(wireGuardPort: Int, amneziaPort: Int) -> String {
        """
        # Managed by gryonixNexus: AmneziaWG answers on the WireGuard port.
        # WireGuard packets start with type 1-4 and three zeros.
        table \(table)
        delete table \(table)
        table \(table) {
            chain prerouting {
                type nat hook prerouting priority dstnat - 10; policy accept;
                udp dport \(wireGuardPort) @th,64,32 != { 0x01000000, 0x02000000, 0x03000000, 0x04000000 } \
        redirect to :\(amneziaPort)
            }
        }

        """
    }

    /// Writes and applies the drop-in, or removes its table
    public static func section(_ context: ServiceContext) -> String {
        guard let port = sharedPort(context) else {
            return """
            rm -f \(path)
            nft delete table \(table) 2>/dev/null || true
            """
        }
        return """
        install -d -m 755 /etc/nftables.d
        cat > \(path) <<'EOF_VPN_SHARE'
        \(dropIn(wireGuardPort: port, amneziaPort: context.settings.amneziaWGPort))EOF_VPN_SHARE
        nft -f \(path)
        """
    }
}
