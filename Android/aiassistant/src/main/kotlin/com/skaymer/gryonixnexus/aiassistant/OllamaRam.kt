package com.skaymer.gryonixnexus.aiassistant

sealed interface RamVerdict {
    data object Enough : RamVerdict
    data class TooLow(val needGb: Int, val haveGb: Int) : RamVerdict
    data object Unknown : RamVerdict
}

/** Rough memory a model needs, from its parameter count. */
object OllamaRam {
    val suggestedModels = listOf("llama3.2:3b", "qwen2.5:7b", "llama3.1:8b", "qwen2.5:14b", "qwen2.5:32b")

    private val mixture = Regex("(\\d+)x(\\d+(?:\\.\\d+)?)b(?![a-z])")
    private val single = Regex("(?<![a-z0-9.])(\\d+(?:\\.\\d+)?)b(?![a-z])")

    fun parametersInBillions(model: String): Double? {
        val name = model.lowercase()
        mixture.find(name)?.let { return it.groupValues[1].toDouble() * it.groupValues[2].toDouble() }
        return single.find(name)?.groupValues?.get(1)?.toDouble()
    }

    fun requiredGb(model: String): Int? {
        val size = parametersInBillions(model) ?: return null
        return when {
            size <= 3 -> 4
            size <= 8 -> 8
            size <= 14 -> 16
            size <= 29 -> 24
            else -> 32
        }
    }

    fun verdict(model: String, machineBytes: Long?): RamVerdict {
        val need = requiredGb(model) ?: return RamVerdict.Unknown
        if (machineBytes == null || machineBytes <= 0) return RamVerdict.Unknown
        val have = Math.round(machineBytes / 1_073_741_824.0).toInt()
        return if (have >= need) RamVerdict.Enough else RamVerdict.TooLow(need, have)
    }
}
