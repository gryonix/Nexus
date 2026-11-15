package com.skaymer.gryonixnexus.app.agent

/** Each machine's agent build, summed up on one run */
class AgentBuildMachines(
    val names: List<String>,
    private val words: Words = Words(),
    private val now: () -> Long = System::currentTimeMillis,
) {
    /** The translated parts of the summary */
    data class Words(
        val done: (String) -> String = { "$it: done" },
        val failed: (String) -> String = { "$it: failed" },
        val building: (String) -> String = { "$it: building" },
        val buildingFor: (String, Int) -> String = { name, minutes -> "$name: building, $minutes min" },
        val waiting: (String) -> String = { "$it: waiting" },
    )

    private sealed interface Phase {
        data class Building(val since: Long) : Phase
        data object Done : Phase
        data object Failed : Phase
    }

    private val phases = java.util.concurrent.ConcurrentHashMap<String, Phase>()

    /** Lines carry the machine's name only when there are several */
    val isSeveral: Boolean get() = names.size > 1

    fun started(name: String) {
        phases[name] = Phase.Building(now())
    }

    fun finished(name: String, ok: Boolean) {
        phases[name] = if (ok) Phase.Done else Phase.Failed
    }

    val anyBuilding: Boolean get() = phases.values.any { it is Phase.Building }

    /** One line of a machine, named when there are several */
    fun line(text: String, name: String): String = if (isSeveral) "$name: $text" else text

    /** Each machine's state, in the given order */
    fun summary(): String = names.joinToString(" · ") { name ->
        when (val phase = phases[name]) {
            Phase.Done -> words.done(name)
            Phase.Failed -> words.failed(name)
            is Phase.Building -> {
                val minutes = ((now() - phase.since) / 60_000).toInt()
                if (minutes < 1) words.building(name) else words.buildingFor(name, minutes)
            }
            null -> words.waiting(name)
        }
    }
}
