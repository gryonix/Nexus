package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentStore

/** The fleet file, without a file */
class InMemoryDeploymentStore(initial: List<Deployment> = emptyList()) : DeploymentStore {
    var contents: List<Deployment> = initial
        private set

    override fun load(): List<Deployment> = contents

    override fun save(deployments: List<Deployment>) {
        contents = deployments
    }
}
