package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** Whose history the explorer is showing */
object HistoryHost {
    fun resolve(deployment: Deployment, requested: SSHHostID?): SSHHostID {
        if (requested != null && deployment.nodes.any { it.sshHost == requested }) {
            return requested
        }
        return deployment.servicesHost
    }
}
