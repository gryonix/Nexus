package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.aiassistant.AIContext
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.metrics.HistoryRange
import com.skaymer.gryonixnexus.app.notify.OperationJournal
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryProbe
import kotlin.time.Duration.Companion.seconds

/** Gathers a week of history, on demand only. */
object AiWeekly {
    suspend fun context(app: GryonixApplication): AIContext {
        val servers = app.fleet.deployments.value.filter { !DemoDeployments.isDemoID(it.id) }
        return AiExplain.weekly(servers.map { digest(app, it) }, OperationJournal.recentLines())
    }

    private suspend fun digest(app: GryonixApplication, server: Deployment): String = try {
        val runner = app.sshRunner(server)
        val points = MetricsHistoryProbe(runner, server.timeouts.quickSeconds.seconds)
            .history(HistoryRange.WEEK.bucket, server.servicesHost)
        AiExplain.digest(server.name, points)
    } catch (failure: Exception) {
        "${server.name}: history unavailable"
    }
}
