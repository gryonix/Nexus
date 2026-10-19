/// A first-visitor site stays VPN-only until its account exists
public enum CaddySetupGuard {
    public static let directory = "/etc/caddy/gryonixnexus-setup"

    /// Sites whose first visitor becomes their administrator
    public static let firstVisitorAdmin: [ServiceID] =
        [.immich, .jellyfin, .homeAssistant, .n8n, .openWebUI, .anythingLLM]

    static let denial = "This site opens to the internet once its first account exists. Connect to your WireGuard VPN to create it."

    public static let rules = """
        @gryonixnexus_setup_relay {
            remote_ip 10.8.0.0/24
            not remote_ip 10.8.0.254/32
        }
        respond @gryonixnexus_setup_relay "\(denial)" 403
        @gryonixnexus_setup_public not remote_ip private_ranges
        respond @gryonixnexus_setup_public "\(denial)" 403
        @gryonixnexus_setup_tunnel header Cf-Connecting-IP *
        respond @gryonixnexus_setup_tunnel "\(denial)" 403

        """

    public static func importLine(_ owner: String) -> String {
        "import \(directory)/\(owner)*"
    }

    /// Without WireGuard nobody could reach a guarded site
    public static func applies(_ owner: String, installed: Set<ServiceID>) -> Bool {
        installed.contains(.wireguardVPN) && firstVisitorAdmin.contains(ServiceID(rawValue: owner))
    }

    public static func guarding(_ site: String, owner: String, installed: Set<ServiceID>) -> String {
        guard applies(owner, installed: installed),
              let at = site.range(of: "import \(VPNPanelService.adminGuardPath)") else { return site }
        let lineStart = site[..<at.lowerBound].lastIndex(of: "\n").map { site.index(after: $0) } ?? site.startIndex
        let indent = site[lineStart..<at.lowerBound]
        return String(site[..<at.lowerBound]) + importLine(owner) + "\n" + indent + String(site[at.lowerBound...])
    }

    public static func armSection(_ owners: [String]) -> String {
        owners.map { owner in
            """

            if ! grep -qE '^[[:space:]]*# gryonixnexus: \(owner)$' /etc/caddy/Caddyfile 2>/dev/null; then
              install -d -m 755 \(directory)
              cat > \(directory)/\(owner) <<'EOF_SETUP_GUARD'
            \(rules)EOF_SETUP_GUARD
              chmod 644 \(directory)/\(owner)
            fi
            """
        }.joined()
    }
}
