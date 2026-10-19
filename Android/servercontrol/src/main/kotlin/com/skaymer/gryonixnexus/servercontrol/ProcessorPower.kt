package com.skaymer.gryonixnexus.servercontrol

/** Idle and full-load package watts by processor model */
object ProcessorPower {
    /** What kind of machine a processor usually sits in */
    enum class Platform { SERVER, DESKTOP, COMPACT }

    data class Figures(val idle: Double, val peak: Double, val platform: Platform)

    private class Rule(pattern: String, val figures: (Double) -> Figures) {
        val regex = Regex(pattern, RegexOption.IGNORE_CASE)

        constructor(pattern: String, idle: Double, peak: Double, platform: Platform) :
            this(pattern, { _: Double -> Figures(idle, peak, platform) })
    }

    /** One package's figures from its model name and cores */
    fun figures(model: String, cores: Int): Figures {
        val name = normalized(model)
        val count = maxOf(cores, 1).toDouble()
        return rules.firstOrNull { it.regex.containsMatchIn(name) }?.figures?.invoke(count) ?: fallback(count)
    }

    fun normalized(model: String): String =
        model.replace("(R)", "").replace("(TM)", "").replace(Regex("\\s+"), " ").trim()

    private fun fallback(cores: Double): Figures {
        val idle = 4 + 0.5 * cores
        return Figures(idle, minOf(idle + 5 * cores, 250.0), Platform.DESKTOP)
    }

    private fun manyCore(idle: Double, perCore: Double, base: Double, floor: Double, ceiling: Double) =
        { cores: Double ->
            Figures(idle + 0.3 * cores, minOf(maxOf(base + perCore * cores, floor), ceiling), Platform.SERVER)
        }

    private val amdRules = listOf(
        Rule("EPYC 3[0-9]{3}\\b", 10.0, 50.0, Platform.COMPACT),
        Rule("EPYC 4[0-9]{3}", 15.0, 90.0, Platform.DESKTOP),
        Rule("EPYC", manyCore(idle = 30.0, perCore = 2.5, base = 120.0, floor = 120.0, ceiling = 400.0)),
        Rule("Threadripper", manyCore(idle = 40.0, perCore = 5.0, base = 100.0, floor = 180.0, ceiling = 350.0)),
        Rule("Ryzen.* [0-9]{3,4}(U|C)\\b", 2.0, 25.0, Platform.COMPACT),
        Rule("Ryzen.* [0-9]{3,4}(HS|HX|H)\\b", 4.0, 55.0, Platform.COMPACT),
        Rule("Ryzen.* [0-9]{4}GE\\b", 4.0, 35.0, Platform.DESKTOP),
        Rule("Ryzen.* [0-9]{4}G\\b", 5.0, 70.0, Platform.DESKTOP),
        Rule("Ryzen 9 .*[0-9]{4}X", 22.0, 150.0, Platform.DESKTOP),
        Rule("Ryzen.* [0-9]{4}X", 18.0, 105.0, Platform.DESKTOP),
        Rule("Ryzen AI", 3.0, 55.0, Platform.COMPACT),
        Rule("Ryzen", 15.0, 75.0, Platform.DESKTOP),
        Rule("Opteron|FX-", 20.0, 110.0, Platform.DESKTOP),
    )

    private val intelRules = listOf(
        Rule("Xeon.* D-[0-9]{4}", 10.0, 50.0, Platform.COMPACT),
        Rule("Xeon.* E3-[0-9]{4}L", 5.0, 25.0, Platform.DESKTOP),
        Rule("Xeon.* (E3-[0-9]{4}|E-2[0-9]{3})", 8.0, 80.0, Platform.DESKTOP),
        Rule("Xeon", manyCore(idle = 10.0, perCore = 5.5, base = 35.0, floor = 45.0, ceiling = 350.0)),
        Rule("\\b(N[0-9]{2,3}|[JN][0-9]{4})\\b", 2.0, 12.0, Platform.COMPACT),
        Rule("Atom", 5.0, 20.0, Platform.COMPACT),
        Rule("Ultra.* [0-9]{3}(U|V)\\b", 2.0, 25.0, Platform.COMPACT),
        Rule("Ultra.* [0-9]{3}H", 4.0, 55.0, Platform.COMPACT),
        Rule("Ultra.* [0-9]{3}K", 10.0, 160.0, Platform.DESKTOP),
        Rule("Ultra", 8.0, 90.0, Platform.DESKTOP),
        Rule("i[3579]-[0-9]{3,5}[A-Z]*(U|Y)", 2.0, 20.0, Platform.COMPACT),
        Rule("i[3579]-[0-9]{3,5}[A-Z]*G[0-9]", 3.0, 28.0, Platform.COMPACT),
        Rule("i[3579]-[0-9]{3,5}HX", 5.0, 90.0, Platform.COMPACT),
        Rule("i[3579]-[0-9]{3,5}H", 4.0, 50.0, Platform.COMPACT),
        Rule("i[3579]-[0-9]{3,5}P", 3.0, 35.0, Platform.COMPACT),
        Rule("i[3579]-[0-9]{3,5}T", 4.0, 35.0, Platform.DESKTOP),
        Rule("i[3579]-[0-9]{3,5}K", 10.0, 150.0, Platform.DESKTOP),
        Rule("i[3579]-[0-9]{3,5}", 7.0, 70.0, Platform.DESKTOP),
        Rule("(Pentium|Celeron).* G[0-9]{4}", 4.0, 50.0, Platform.DESKTOP),
        Rule("Pentium|Celeron", 3.0, 15.0, Platform.COMPACT),
    )

    private val otherRules = listOf(
        Rule("Ampere|Altra|Neoverse", manyCore(idle = 25.0, perCore = 2.8, base = 0.0, floor = 40.0, ceiling = 250.0)),
    )

    private val rules = amdRules + intelRules + otherRules
}
