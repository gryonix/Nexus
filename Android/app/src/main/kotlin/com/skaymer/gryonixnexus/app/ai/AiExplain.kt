package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.aiassistant.AIContext
import com.skaymer.gryonixnexus.aiassistant.AIContextKind
import com.skaymer.gryonixnexus.aiassistant.AIContextSection
import com.skaymer.gryonixnexus.aiassistant.AIUsageSample
import com.skaymer.gryonixnexus.aiassistant.AIWeeklyDigest
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import com.skaymer.gryonixnexus.servercontrol.ServerHealthFacts
import com.skaymer.gryonixnexus.servercontrol.ServerProblem

/** Builds read-only contexts from data the app already holds. */
object AiExplain {
    fun problem(problem: ServerProblem, facts: List<ServerHealthFacts>, deployments: List<Deployment>, title: String): AIContext {
        val names = deployments.associate { it.id to it.name }
        val lines = facts.filter { problem in it.problems }.map { fact ->
            buildList {
                add(names[fact.id] ?: "server")
                if (fact.unreachable) add("unreachable")
                fact.diskFraction?.let { add("disk %.0f%% used".format(it * 100)) }
                fact.servicesDown?.let { add("$it services need attention") }
                fact.updatesPending?.let { add("$it updates waiting") }
            }.joinToString(", ")
        }
        return AIContext(AIContextKind.PROBLEM, title, listOf(AIContextSection("Affected servers", lines.joinToString("\n"))))
    }

    fun service(name: String, server: String, logs: String) =
        AIContext(AIContextKind.SERVICE, "$name on $server", listOf(AIContextSection("Recent logs", logs)))

    fun operation(title: String, error: String?, log: String) = AIContext(
        AIContextKind.OPERATION, title,
        listOf(AIContextSection("Error", error.orEmpty()), AIContextSection("Output", log)),
    )

    fun terminal(kind: AIContextKind, server: String, label: String, text: String, title: String) =
        AIContext(kind, title.replace("{0}", server), listOf(AIContextSection(label, text)))

    fun weekly(digests: List<String>, events: List<String>) = AIContext(
        AIContextKind.WEEKLY, "Weekly summary",
        listOf(
            AIContextSection("Metrics, last 7 days", digests.joinToString("\n")),
            AIContextSection("Recent events", events.joinToString("\n")),
        ),
    )

    fun digest(server: String, points: List<MetricsHistoryPoint>): String = AIWeeklyDigest.lines(
        server,
        points.map {
            AIUsageSample(
                it.date.toEpochMilli(), it.cpuPercent,
                if (it.memTotalBytes > 0) it.memUsedBytes.toDouble() / it.memTotalBytes else null,
                if (it.diskTotalBytes > 0) it.diskUsedBytes.toDouble() / it.diskTotalBytes else null,
                it.temperatureCelsius,
            )
        },
    )
}
