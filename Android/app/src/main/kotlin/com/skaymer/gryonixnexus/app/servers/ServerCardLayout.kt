package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize

/** How the fleet is laid out into rows */
object ServerCardLayout {
    fun size(of: Deployment, whenUnset: ServerCardSize): ServerCardSize =
        of.cardSize ?: whenUnset

    fun indicatorStyle(
        of: Deployment,
        whenUnset: MetricsIndicatorStyle
    ): MetricsIndicatorStyle = of.metricsIndicatorStyle ?: whenUnset

    fun rows(of: List<Deployment>, whenUnset: ServerCardSize): List<List<Deployment>> {
        val rows = mutableListOf<MutableList<Deployment>>()
        var waiting: Int? = null
        for (deployment in of) {
            if (size(deployment, whenUnset) != ServerCardSize.COMPACT) {
                rows.add(mutableListOf(deployment))
                continue
            }
            val index = waiting
            if (index != null) {
                rows[index].add(deployment)
                waiting = null
            } else {
                rows.add(mutableListOf(deployment))
                waiting = rows.size - 1
            }
        }
        return rows
    }
}
