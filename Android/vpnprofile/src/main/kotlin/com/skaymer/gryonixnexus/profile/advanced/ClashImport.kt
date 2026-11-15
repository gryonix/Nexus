package com.skaymer.gryonixnexus.profile.advanced

/** Reads a Clash profile: proxies and a subset of rules. */
object ClashImport {
    fun looksLikeClash(text: String): Boolean = "proxies:" in text && !text.startsWith("vless://")

    fun parse(text: String): AdvancedImportReport {
        val root = MiniYaml.parse(text)
        val servers = mutableListOf<AdvancedServer>()
        val rules = mutableListOf<AdvancedRule>()
        val skipped = mutableListOf<AdvancedImportReport.Skipped>()
        for (entry in root["proxies"]?.list.orEmpty()) {
            when (val outcome = server(entry)) {
                is SubscriptionImport.Outcome.Server -> servers.add(outcome.server)
                is SubscriptionImport.Outcome.Skip -> skipped.add(outcome.skipped)
            }
        }
        for (line in root["rules"]?.list.orEmpty()) {
            val raw = line.string ?: continue
            val rule = rule(raw)
            if (rule.first != null) rules.add(rule.first!!) else skipped.add(rule.second!!)
        }
        return AdvancedImportReport(servers, rules, skipped)
    }

    private fun server(entry: YamlValue): SubscriptionImport.Outcome {
        val name = entry["name"]?.string.orEmpty()
        val type = entry["type"]?.string?.lowercase().orEmpty()
        val host = entry["server"]?.string
        val port = entry["port"]?.string?.toIntOrNull()
        fun skip(reason: String) = SubscriptionImport.Outcome.Skip(AdvancedImportReport.Skipped(name, reason))
        if (host == null || port == null) return skip("the proxy is incomplete")
        val (kind, fields) = when (type) {
            "ss" -> ServerKind.SHADOWSOCKS to shadowsocks(entry)
            "vmess" -> ServerKind.VMESS to stream(entry, "uuid")
            "vless" -> ServerKind.VLESS to stream(entry, "uuid")
            "trojan" -> ServerKind.TROJAN to stream(entry, "password")
            "wireguard" -> ServerKind.WIREGUARD to wireguard(entry)
            "hysteria2" -> ServerKind.HYSTERIA2 to hysteria2(entry)
            else -> return skip("$type is not supported by the VPN engine")
        }
        if (fields == null) return skip(reason(entry, type))
        val all = fields.toMutableMap()
        if (type == "vmess") {
            all["alterId"] = entry["alterId"]?.string ?: "0"
            all["scy"] = entry["cipher"]?.string ?: "auto"
        }
        if (type == "vless") entry["flow"]?.string?.let { all["flow"] = it }
        return SubscriptionImport.Outcome.Server(AdvancedServer.create(kind, name, host, port, all))
    }

    private fun reason(entry: YamlValue, type: String): String {
        if (type == "ss") return if (entry["plugin"] != null) "plugins are not supported" else "the proxy is incomplete"
        if (type == "hysteria2") return "the proxy is incomplete"
        return "transport ${entry["network"]?.string ?: "tcp"} is not supported"
    }

    private fun shadowsocks(entry: YamlValue): Map<String, String>? {
        val method = entry["cipher"]?.string
        val password = entry["password"]?.string
        if (entry["plugin"] != null || method == null || password == null) return null
        return mapOf("method" to method, "password" to password)
    }

    private fun hysteria2(entry: YamlValue): Map<String, String>? {
        val password = entry["password"]?.string ?: return null
        val fields = linkedMapOf("password" to password)
        entry["sni"]?.string?.let { fields["sni"] = it }
        if (entry["skip-cert-verify"]?.string == "true") fields["insecure"] = "1"
        entry["obfs"]?.string?.let { fields["obfs"] = it }
        entry["obfs-password"]?.string?.let { fields["obfsPassword"] = it }
        return fields
    }

    private fun wireguard(entry: YamlValue): Map<String, String>? {
        val key = entry["private-key"]?.string
        val peer = entry["public-key"]?.string
        val address = entry["ip"]?.string
        if (key == null || peer == null || address == null) return null
        val fields = linkedMapOf("secretKey" to key, "publicKey" to peer, "address" to address)
        entry["mtu"]?.string?.let { fields["mtu"] = it }
        entry["pre-shared-key"]?.string?.let { fields["preSharedKey"] = it }
        entry["reserved"]?.list?.let { list -> fields["reserved"] = list.mapNotNull { it.string }.joinToString(",") }
        return fields
    }

    private fun stream(entry: YamlValue, secret: String): Map<String, String>? {
        val value = entry[secret]?.string ?: return null
        val network = entry["network"]?.string ?: "tcp"
        if (network !in SubscriptionImport.carriedNetworks) return null
        val reality = entry["reality-opts"]
        val tls = entry["tls"]?.string == "true" || entry["type"]?.string == "trojan"
        val security = if (reality != null) "reality" else if (tls) "tls" else "none"
        val fields = linkedMapOf(secret to value, "network" to network, "security" to security)
        for ((key, name) in listOf("client-fingerprint" to "fp", "servername" to "sni", "sni" to "sni")) {
            entry[key]?.string?.let { if (name !in fields) fields[name] = it }
        }
        if (entry["skip-cert-verify"]?.string == "true") fields["insecure"] = "1"
        reality?.get("public-key")?.string?.let { fields["pbk"] = it }
        reality?.get("short-id")?.string?.let { fields["sid"] = it }
        addTransport(fields, entry)
        return fields
    }

    private fun addTransport(fields: MutableMap<String, String>, entry: YamlValue) {
        entry["ws-opts"]?.let { ws ->
            ws["path"]?.string?.let { fields["path"] = it }
            ws["headers"]?.get("Host")?.string?.let { fields["host"] = it }
        }
        entry["grpc-opts"]?.get("grpc-service-name")?.string?.let { fields["serviceName"] = it }
        (entry["http-upgrade-opts"] ?: entry["httpupgrade-opts"])?.let { upgrade ->
            upgrade["path"]?.string?.let { fields["path"] = it }
            upgrade["host"]?.string?.let { fields["host"] = it }
        }
    }

    private val ruleKinds = mapOf(
        "DOMAIN" to RuleKind.DOMAIN, "DOMAIN-SUFFIX" to RuleKind.DOMAIN_SUFFIX,
        "DOMAIN-KEYWORD" to RuleKind.KEYWORD, "IP-CIDR" to RuleKind.IP, "IP-CIDR6" to RuleKind.IP,
        "GEOIP" to RuleKind.GEOIP,
    )

    private fun rule(line: String): Pair<AdvancedRule?, AdvancedImportReport.Skipped?> {
        val parts = line.split(',').map { it.trim() }
        val kind = ruleKinds[parts.first().uppercase()]
        if (parts.size < 3 || kind == null) {
            val final = parts.first().uppercase().let { it == "MATCH" || it == "FINAL" }
            val reason = if (final) "set the final rule by hand" else "${parts.first()} rules are not supported"
            return null to AdvancedImportReport.Skipped(line, reason)
        }
        return AdvancedRule(kind, parts[1], action(parts[2])) to null
    }

    fun action(policy: String): RuleAction = when (policy.uppercase()) {
        "DIRECT" -> RuleAction.DIRECT
        "REJECT", "REJECT-DROP", "REJECT-TINYGIF" -> RuleAction.BLOCK
        else -> RuleAction.PROXY
    }
}
