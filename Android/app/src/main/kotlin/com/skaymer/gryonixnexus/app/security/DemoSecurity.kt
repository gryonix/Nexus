package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import com.skaymer.gryonixnexus.servercontrol.SshPasswordAccess
import com.skaymer.gryonixnexus.servercontrol.SshUserAccess
import com.skaymer.gryonixnexus.servercontrol.SshUsers

/** Invented protection for the demo fleet */
object DemoSecurity {
    fun status(deployment: Deployment): HostSecurityStatus? {
        if (!DemoDeployments.isDemoID(deployment.id)) return null
        return HostSecurityStatus(
            isPresent = true,
            engineRunning = true,
            bouncerRunning = true,
            engineVersion = "v1.8.1",
            alertsLast24h = 49,
            localBans = 2,
            communityBlocklistIps = 17_707,
            packetsDropped = 17_800,
            topScenarios = listOf(
                HostSecurityStatus.Scenario("crowdsecurity/ssh-bf", 37),
                HostSecurityStatus.Scenario("crowdsecurity/ssh-slow-bf", 11),
            ),
            recentBans = listOf(
                HostSecurityStatus.Ban(
                    ip = "193.233.199.37",
                    country = "RU",
                    scenario = "crowdsecurity/ssh-slow-bf",
                    at = "2026-09-12T15:52:20Z",
                ),
            ),
        )
    }

    /** An invented server signs in with a key */
    fun sshAccess(deployment: Deployment): SshPasswordAccess? {
        if (!DemoDeployments.isDemoID(deployment.id)) return null
        return SshPasswordAccess(
            passwordLoginOpen = false,
            isKnown = true,
            appKeyPresent = true,
            dropInPresent = true,
            sshdPresent = true,
            loginUser = deployment.entry.user,
            detail = "",
        )
    }

    /** Accounts that refuse passwords, per demo server */
    private val keyOnly = java.util.concurrent.ConcurrentHashMap<String, Set<String>>()

    private val hostOpen = java.util.concurrent.ConcurrentHashMap<String, Boolean>()

    private fun accounts(deployment: Deployment): List<String> = listOf(deployment.entry.user, "root", "backup")

    /** Three invented accounts, one without a key */
    fun sshUsers(deployment: Deployment): SshUsers? {
        if (!DemoDeployments.isDemoID(deployment.id)) return null
        val login = deployment.entry.user
        val closed = keyOnly.getOrPut(deployment.id) { setOf(login) }
        val host = sshAccess(deployment)!!.copy(passwordLoginOpen = hostOpen[deployment.id] ?: false)
        return SshUsers(
            users = accounts(deployment).map { name ->
                SshUserAccess(
                    name = name,
                    passwordLoginOpen = name !in closed,
                    isKnown = true,
                    hasKeys = name != "backup",
                    appKeyPresent = name == login,
                    isLoginUser = name == login,
                )
            },
            host = host,
            detail = "",
            isKnown = true,
        )
    }

    fun setKeyOnlyUsers(deployment: Deployment, everyone: Boolean, users: List<String>): SshUsers? {
        if (!DemoDeployments.isDemoID(deployment.id)) return null
        keyOnly[deployment.id] = if (everyone) accounts(deployment).toSet() else users.toSet()
        hostOpen[deployment.id] = !everyone
        return sshUsers(deployment)
    }
}
