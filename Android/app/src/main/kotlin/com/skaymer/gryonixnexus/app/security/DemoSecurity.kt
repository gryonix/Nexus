package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import com.skaymer.gryonixnexus.servercontrol.SshPasswordAccess

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
}
