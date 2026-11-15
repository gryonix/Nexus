package com.skaymer.gryonixnexus.servercontrol

/** The kinds of trouble the dashboard counts */
enum class ServerProblem { UNREACHABLE, DISK_ALMOST_FULL, SERVICE_DOWN, UPDATES_PENDING }

/** What is known about one server's health */
data class ServerHealthFacts(
    val id: String,
    val unreachable: Boolean = false,
    /** Fraction of the disk in use, when known */
    val diskFraction: Double? = null,
    val servicesDown: Int? = null,
    val updatesPending: Int? = null,
) {
    val problems: Set<ServerProblem>
        get() = buildSet {
            if (unreachable) add(ServerProblem.UNREACHABLE)
            if (diskFraction != null && diskFraction >= ServerProblems.DISK_THRESHOLD) add(ServerProblem.DISK_ALMOST_FULL)
            if ((servicesDown ?: 0) > 0) add(ServerProblem.SERVICE_DOWN)
            if ((updatesPending ?: 0) > 0) add(ServerProblem.UPDATES_PENDING)
        }
}

/** Counts and filters over the fleet */
object ServerProblems {
    const val DISK_THRESHOLD = 0.9

    fun counts(facts: List<ServerHealthFacts>): Map<ServerProblem, Int> =
        facts.flatMap { it.problems }.groupingBy { it }.eachCount()

    fun ids(problem: ServerProblem, facts: List<ServerHealthFacts>): Set<String> =
        facts.filter { problem in it.problems }.map { it.id }.toSet()
}

/** Offline servers last, the rest in the user's order */
object ServerListOrdering {
    fun <T> ordered(items: List<T>, isOffline: (T) -> Boolean): List<T> {
        val (offline, online) = items.partition(isOffline)
        return online + offline
    }
}
