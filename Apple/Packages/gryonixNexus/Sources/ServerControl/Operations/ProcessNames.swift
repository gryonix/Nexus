import Foundation

/// Readable names for programs a server commonly runs
public enum ProcessNames {
    /// A matcher: program name, or text anywhere in the command
    struct Rule {
        let names: [String]
        let mentions: [String]
        let label: String
    }

    static let rules: [Rule] = [
        Rule(names: ["hass"], mentions: ["-m homeassistant"], label: "Home Assistant"),
        Rule(names: [], mentions: ["zigbee2mqtt"], label: "Zigbee2MQTT"),
        Rule(names: [], mentions: ["n8n"], label: "n8n"),
        Rule(names: [], mentions: ["immich"], label: "Immich"),
        Rule(names: ["puma", "sidekiq", "gitaly", "gitlab-workhorse"], mentions: ["gitlab"], label: "GitLab"),
        Rule(names: ["bedrock_server"], mentions: [], label: "Minecraft Bedrock"),
        Rule(names: [], mentions: ["minecraft", "paper.jar", "server.jar", "forge"], label: "Minecraft"),
        Rule(names: ["mosquitto"], mentions: [], label: "Mosquitto"),
        Rule(names: ["gryonixnexusd"], mentions: [], label: "gryonixNexus"),
        Rule(names: ["dockerd", "containerd", "containerd-shim-runc-v2", "docker-proxy"], mentions: [], label: "Docker"),
        Rule(names: ["caddy"], mentions: [], label: "Caddy"),
        Rule(names: ["mariadbd"], mentions: [], label: "MariaDB"),
        Rule(names: ["mysqld"], mentions: [], label: "MySQL"),
        Rule(names: ["postgres"], mentions: [], label: "PostgreSQL"),
        Rule(names: ["redis-server"], mentions: [], label: "Redis"),
        Rule(names: ["nginx"], mentions: [], label: "nginx"),
        Rule(names: ["apache2", "httpd"], mentions: [], label: "Apache"),
        Rule(names: ["ollama"], mentions: [], label: "Ollama"),
        Rule(names: ["vaultwarden"], mentions: [], label: "Vaultwarden"),
        Rule(names: ["clamd", "freshclam"], mentions: [], label: "ClamAV"),
        Rule(names: ["rspamd"], mentions: [], label: "Rspamd"),
        Rule(names: ["dovecot", "imap", "imap-login", "auth"], mentions: ["dovecot"], label: "Dovecot"),
        Rule(names: [], mentions: ["postfix"], label: "Postfix"),
        Rule(names: ["sogod"], mentions: [], label: "SOGo"),
        Rule(names: ["crowdsec", "crowdsec-firewall-bouncer"], mentions: [], label: "CrowdSec"),
        Rule(names: ["xray"], mentions: [], label: "Xray"),
        Rule(names: ["ss-server", "ssserver"], mentions: [], label: "Shadowsocks"),
        Rule(names: ["openvpn"], mentions: [], label: "OpenVPN"),
        Rule(names: ["headscale"], mentions: [], label: "Headscale"),
        Rule(names: ["tailscaled"], mentions: [], label: "Tailscale"),
        Rule(names: ["AdGuardHome"], mentions: [], label: "AdGuard Home"),
        Rule(names: ["pihole-FTL"], mentions: [], label: "Pi-hole"),
        Rule(names: ["jellyfin"], mentions: [], label: "Jellyfin"),
        Rule(names: ["qdrant"], mentions: [], label: "Qdrant"),
        Rule(names: ["gitea", "forgejo"], mentions: [], label: "Forgejo"),
        Rule(names: ["unbound"], mentions: [], label: "Unbound"),
        Rule(names: ["sshd"], mentions: [], label: "SSH"),
        Rule(names: ["avahi-daemon"], mentions: [], label: "Avahi"),
        Rule(names: ["dbus-daemon", "dbus-broker"], mentions: [], label: "D-Bus"),
        Rule(names: ["init", "journalctl"], mentions: [], label: "systemd"),
        Rule(names: ["java"], mentions: [], label: "Java"),
        Rule(names: ["node"], mentions: [], label: "Node.js"),
        Rule(names: ["python3", "python"], mentions: [], label: "Python"),
    ]

    /// A readable name, or nil for an unknown program
    public static func friendly(_ command: String) -> String? {
        if command.hasPrefix("[") { return command.hasPrefix("[wg-crypt") ? "WireGuard" : "Linux" }
        let program = TopProcesses.executable(command)
        if program.hasPrefix("php-fpm") || program.hasPrefix("php") { return "PHP" }
        if program.hasPrefix("systemd") { return "systemd" }
        if program.hasPrefix("containerd-shim") { return "Docker" }
        let lowered = command.lowercased()
        return rules.first { rule in
            rule.names.contains(program) || rule.mentions.contains { lowered.contains($0) }
        }?.label
    }
}
