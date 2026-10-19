package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DefaultSecurityPolicy
import com.skaymer.gryonixnexus.core.Domain
import com.skaymer.gryonixnexus.core.SecurityPolicy
import com.skaymer.gryonixnexus.core.ServerNode

/** Input for the mail recipe */
data class MailRecipeInput(
    val domain: Domain,
    /** Further domains the same server answers on */
    val additionalDomains: List<Domain> = emptyList(),
    /** e.g */
    val hostname: String,
    /** Hostname the mail IP's PTR record should resolve to */
    val reverseDNSHostname: String? = null,
    val topology: Topology,
    /** Public-internet (default) or local-network-only */
    val scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET,
    val servers: List<ServerNode>,
    val security: SecurityPolicy = DefaultSecurityPolicy(),
    val dashboardAccess: DashboardAccessInput? = null,
    /** Self-hosted services to install */
    val services: Set<ServiceID> = setOf(ServiceID.MAILCOW),
    val serviceSettings: ServiceSettings = ServiceSettings(),
    val language: AppLanguage = AppLanguage.EN
)
