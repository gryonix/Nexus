package com.skaymer.gryonixnexus.app.mail

import com.skaymer.gryonixnexus.app.access.InstallReportImport
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.VaultEntry
import java.util.Locale

object MailboxVault {
    fun entry(deployment: Deployment, address: String, password: String, now: Long, writer: String): VaultEntry {
        val login = address.trim().lowercase(Locale.ROOT)
        val host = InstallReportImport.hosts(deployment)
            .first { it.second == deployment.hostRunning(ServiceID.DOCKER_MAILSERVER) }.first
        val title = "Mailbox: $login"
        return VaultEntry(id = "$host|$title", host = host, title = title,
            login = login, password = password, updated_at = now, updated_by = writer)
    }
}
