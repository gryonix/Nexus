package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.Deployment

object FleetOrder {
    fun moved(deployments: List<Deployment>, from: Int, to: Int): List<Deployment> {
        if (from !in deployments.indices || to !in deployments.indices || from == to) {
            return deployments
        }
        val list = deployments.toMutableList()
        list.add(to, list.removeAt(from))
        return list
    }

    fun canMoveUp(index: Int): Boolean = index > 0

    fun canMoveDown(index: Int, count: Int): Boolean = index < count - 1
}
