package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.L10nServices

data class ReportedAccount(
    val title: String,
    val website: String? = null,
    val login: String? = null,
    val password: String? = null,
    val token: String? = null,
) {
    companion object {
        fun accounts(sections: List<InstallReportParser.Section>): List<ReportedAccount> =
            sections.mapNotNull { account(it) }

        private fun account(section: InstallReportParser.Section): ReportedAccount? {
            var website: String? = null
            var login: String? = null
            var password: String? = null
            var token: String? = null
            for (field in section.fields) {
                when {
                    field.label == InstallReportParser.URL -> website = cleanURL(field.value)
                    field.label in Labels.password -> password = field.value
                    field.label in Labels.token -> token = field.value
                    field.label in Labels.login -> login = field.value
                }
            }
            if (website == null || !website.startsWith("http")) return null
            return ReportedAccount(section.title, website, login, password, token)
        }

        /** Strip the trailing " (directory: …)" annotation the report appends */
        private fun cleanURL(value: String): String {
            val marker = value.indexOf("  (")
            return if (marker >= 0) value.substring(0, marker) else value
        }

        private object Labels {
            val password: Set<String> = AppLanguage.entries.flatMap {
                listOf(
                    L10nServices.passwordLabel(it),
                    L10nServices.passwordGeneratedOnServerLabel(it),
                )
            }.toSet()
            val login: Set<String> =
                AppLanguage.entries.map { L10nServices.administratorLabel(it) }.toSet()
            val token: Set<String> =
                AppLanguage.entries.map { L10nServices.vaultwardenAdminTokenLabel(it) }.toSet()
        }
    }
}

data class AccessAccount(
    val host: String,
    val title: String,
    val website: String?,
    val reportLogin: String,
    val reportPassword: String,
    val reportToken: String,
    val login: String,
    val password: String,
    val token: String,
    val hasToken: Boolean,
    val isVaultwarden: Boolean,
    val loadedLogin: String = login,
    val loadedPassword: String = password,
    val loadedToken: String = token,
    val updatedAt: Long = 0,
    val updatedBy: String = "",
) {
    val id: String get() = AccessCredentialStore.key(host, title)

    val isChanged: Boolean
        get() = login != loadedLogin || password != loadedPassword || token != loadedToken

    /** Nothing worth sending */
    val isEmptyCredential: Boolean
        get() = login.isEmpty() && password.isEmpty() && token.isEmpty()

    fun markingLoaded(): AccessAccount =
        copy(loadedLogin = login, loadedPassword = password, loadedToken = token)

    fun override(): AccessCredential? {
        val credential = AccessCredential(
            login = login.takeIf { it != reportLogin && it.isNotEmpty() },
            password = password.takeIf { it != reportPassword && it.isNotEmpty() },
            token = token.takeIf { it != reportToken && it.isNotEmpty() },
        )
        return credential.takeIf { !it.isEmpty }
    }

    companion object {
        fun fromServer(entry: gryonixnexusd.v1.VaultEntry): AccessAccount = AccessAccount(
            host = entry.host,
            title = entry.title,
            website = entry.website.ifEmpty { null },
            reportLogin = "",
            reportPassword = "",
            reportToken = "",
            login = entry.login,
            password = entry.password,
            token = entry.token,
            hasToken = entry.token.isNotEmpty(),
            isVaultwarden = entry.title.lowercase().startsWith("vaultwarden"),
            loadedLogin = entry.login,
            loadedPassword = entry.password,
            loadedToken = entry.token,
            updatedAt = entry.updated_at,
            updatedBy = entry.updated_by,
        )

        fun cards(
            host: String,
            sections: List<InstallReportParser.Section>,
            overrides: Map<String, AccessCredential>,
        ): List<AccessAccount> = ReportedAccount.accounts(sections).map { reported ->
            val override = overrides[AccessCredentialStore.key(host, reported.title)]
            AccessAccount(
                host = host,
                title = reported.title,
                website = reported.website,
                reportLogin = reported.login.orEmpty(),
                reportPassword = reported.password.orEmpty(),
                reportToken = reported.token.orEmpty(),
                login = override?.login ?: reported.login.orEmpty(),
                password = override?.password ?: reported.password.orEmpty(),
                token = override?.token ?: reported.token.orEmpty(),
                hasToken = reported.token != null || override?.token?.isNotEmpty() == true,
                isVaultwarden = reported.title.lowercase().startsWith("vaultwarden"),
            )
        }
    }
}

/** How a card names the machine that printed its report */
sealed interface AccessHostTitle {
    data object VPS : AccessHostTitle
    data object LocalServer : AccessHostTitle

    /** A single-machine deployment, or a host id that names nothing */
    data object Server : AccessHostTitle

    data class Named(val name: String) : AccessHostTitle

    companion object {
        fun of(deployment: com.skaymer.gryonixnexus.servercontrol.Deployment, host: String):
            AccessHostTitle = when (host) {
            "vps" -> VPS
            "home" -> LocalServer
            "single" -> Server
            else -> {
                val node = deployment.nodes.firstOrNull { it.id == host }
                when {
                    node == null -> Server
                    node.name.isNotEmpty() -> Named(node.name)
                    else -> Named(node.endpoint.host)
                }
            }
        }
    }
}
