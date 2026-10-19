package com.skaymer.gryonixnexus.servercontrol

/** Readable names for programs a server commonly runs */
object ProcessNames {
    /** A matcher: program name, or text anywhere in the command */
    internal data class Rule(val names: List<String>, val mentions: List<String>, val label: String)

    internal val rules = listOf(
        Rule(listOf("hass"), listOf("-m homeassistant"), "Home Assistant"),
        Rule(emptyList(), listOf("zigbee2mqtt"), "Zigbee2MQTT"),
        Rule(emptyList(), listOf("n8n"), "n8n"),
        Rule(emptyList(), listOf("immich"), "Immich"),
        Rule(listOf("puma", "sidekiq", "gitaly", "gitlab-workhorse"), listOf("gitlab"), "GitLab"),
        Rule(listOf("bedrock_server"), emptyList(), "Minecraft Bedrock"),
        Rule(emptyList(), listOf("minecraft", "paper.jar", "server.jar", "forge"), "Minecraft"),
        Rule(listOf("mosquitto"), emptyList(), "Mosquitto"),
        Rule(listOf("gryonixnexusd"), emptyList(), "gryonixNexus"),
        Rule(listOf("dockerd", "containerd", "containerd-shim-runc-v2", "docker-proxy"), emptyList(), "Docker"),
        Rule(listOf("caddy"), emptyList(), "Caddy"),
        Rule(listOf("mariadbd"), emptyList(), "MariaDB"),
        Rule(listOf("mysqld"), emptyList(), "MySQL"),
        Rule(listOf("postgres"), emptyList(), "PostgreSQL"),
        Rule(listOf("redis-server"), emptyList(), "Redis"),
        Rule(listOf("nginx"), emptyList(), "nginx"),
        Rule(listOf("apache2", "httpd"), emptyList(), "Apache"),
        Rule(listOf("ollama"), emptyList(), "Ollama"),
        Rule(listOf("vaultwarden"), emptyList(), "Vaultwarden"),
        Rule(listOf("clamd", "freshclam"), emptyList(), "ClamAV"),
        Rule(listOf("rspamd"), emptyList(), "Rspamd"),
        Rule(listOf("dovecot", "imap", "imap-login", "auth"), listOf("dovecot"), "Dovecot"),
        Rule(emptyList(), listOf("postfix"), "Postfix"),
        Rule(listOf("sogod"), emptyList(), "SOGo"),
        Rule(listOf("crowdsec", "crowdsec-firewall-bouncer"), emptyList(), "CrowdSec"),
        Rule(listOf("xray"), emptyList(), "Xray"),
        Rule(listOf("ss-server", "ssserver"), emptyList(), "Shadowsocks"),
        Rule(listOf("openvpn"), emptyList(), "OpenVPN"),
        Rule(listOf("headscale"), emptyList(), "Headscale"),
        Rule(listOf("tailscaled"), emptyList(), "Tailscale"),
        Rule(listOf("AdGuardHome"), emptyList(), "AdGuard Home"),
        Rule(listOf("pihole-FTL"), emptyList(), "Pi-hole"),
        Rule(listOf("jellyfin"), emptyList(), "Jellyfin"),
        Rule(listOf("qdrant"), emptyList(), "Qdrant"),
        Rule(listOf("gitea", "forgejo"), emptyList(), "Forgejo"),
        Rule(listOf("unbound"), emptyList(), "Unbound"),
        Rule(listOf("sshd"), emptyList(), "SSH"),
        Rule(listOf("avahi-daemon"), emptyList(), "Avahi"),
        Rule(listOf("dbus-daemon", "dbus-broker"), emptyList(), "D-Bus"),
        Rule(listOf("init", "journalctl"), emptyList(), "systemd"),
        Rule(listOf("java"), emptyList(), "Java"),
        Rule(listOf("node"), emptyList(), "Node.js"),
        Rule(listOf("python3", "python"), emptyList(), "Python"),
    )

    /** A readable name, or null for an unknown program */
    fun friendly(command: String): String? {
        if (command.startsWith("[")) return if (command.startsWith("[wg-crypt")) "WireGuard" else "Linux"
        val program = TopProcesses.executable(command)
        if (program.startsWith("php-fpm") || program.startsWith("php")) return "PHP"
        if (program.startsWith("systemd")) return "systemd"
        if (program.startsWith("containerd-shim")) return "Docker"
        val lowered = command.lowercase()
        return rules.firstOrNull { rule ->
            program in rule.names || rule.mentions.any { lowered.contains(it) }
        }?.label
    }
}
