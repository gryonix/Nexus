package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ServiceContext

/** The speaker's extra settings, as shairport-sync.conf */
object ShairportSyncOptions {
    /** How one option's value is checked and written */
    sealed class Kind {
        data class Choice(val allowed: List<String>) : Kind()
        data class Number(val low: Double, val high: Double) : Kind()
        data object Control : Kind()
    }

    data class Option(val section: String, val key: String, val kind: Kind)

    /** Every option the app may set, in file order */
    val options: List<Option> = listOf(
        Option("general", "interpolation", Kind.Choice(listOf("auto", "basic", "soxr"))),
        Option("general", "volume_range_db", Kind.Number(30.0, 100.0)),
        Option("general", "volume_max_db", Kind.Number(-96.0, 24.0)),
        Option("general", "ignore_volume_control", Kind.Choice(listOf("yes", "no"))),
        Option("general", "default_airplay_volume", Kind.Number(-30.0, 0.0)),
        Option("general", "audio_backend_latency_offset_in_seconds", Kind.Number(-1.0, 1.0)),
        Option("general", "audio_backend_buffer_desired_length_in_seconds", Kind.Number(0.01, 1.5)),
        Option("general", "drift_tolerance_in_seconds", Kind.Number(0.001, 0.02)),
        Option("general", "allow_session_interruption", Kind.Choice(listOf("yes", "no"))),
        Option("general", "session_timeout", Kind.Number(20.0, 3600.0)),
        Option("alsa", "mixer_control_name", Kind.Control),
        Option("alsa", "output_rate", Kind.Choice(listOf("auto", "44100", "88200", "176400", "352800"))),
        Option("alsa", "output_format", Kind.Choice(listOf("auto", "S16", "S16_LE", "S24", "S24_3LE", "S32"))),
        Option("alsa", "disable_standby_mode", Kind.Choice(listOf("never", "auto", "always"))),
        Option("alsa", "disable_synchronization", Kind.Choice(listOf("yes", "no"))),
        Option("cec", "cec_volume", Kind.Choice(listOf("yes", "no"))),
        Option("cec", "cec_volume_min", Kind.Number(0.0, 100.0)),
        Option("cec", "cec_volume_max", Kind.Number(1.0, 100.0)),
        Option("cec", "cec_tv_wakes", Kind.Choice(listOf("yes", "no"))),
        Option("cec", "cec_tv_wait", Kind.Number(10.0, 180.0)),
        Option("cec", "cec_keep_connected", Kind.Choice(listOf("yes", "no"))),
        Option("cec", "cec_off_delay", Kind.Number(1.0, 60.0)),
        Option("cec", "cec_grace", Kind.Number(5.0, 120.0)),
    )

    /** The speaker's own volume, moved over HDMI */
    data class CecVolume(val enabled: Boolean, val lowest: Int, val highest: Int, val tvOff: Boolean = true,
        val tvWait: Int = 60, val disconnect: Boolean = true, val offDelay: Int = 2, val grace: Int = 15)

    const val CEC_PIPE_DIRECTORY = "/run/shairport-sync"
    const val CEC_DEFAULT_LOWEST = 1
    const val CEC_DEFAULT_HIGHEST = 40

    /** HDMI volume settings, defaults where missing or bad */
    fun cecVolume(context: ServiceContext): CecVolume {
        val given = parsed(context.settings.shairportOptions)
        fun number(key: String, fallback: Int): Int {
            val text = given.lastOrNull { it.first == key }?.second ?: return fallback
            val kind = options.first { it.key == key }.kind
            return if (rendered(kind, text) != null) text.toIntOrNull() ?: fallback else fallback
        }
        val lowest = number("cec_volume_min", CEC_DEFAULT_LOWEST)
        val highest = number("cec_volume_max", CEC_DEFAULT_HIGHEST)
        return CecVolume(
            enabled = given.lastOrNull { it.first == "cec_volume" }?.second == "yes",
            lowest = minOf(lowest, highest - 1),
            highest = highest,
            tvOff = given.lastOrNull { it.first == "cec_tv_wakes" }?.second != "yes",
            tvWait = number("cec_tv_wait", 60),
            disconnect = given.lastOrNull { it.first == "cec_keep_connected" }?.second != "yes",
            offDelay = number("cec_off_delay", 2),
            grace = number("cec_grace", 15),
        )
    }

    /** The options string as key and value pairs */
    fun parsed(text: String): List<Pair<String, String>> =
        text.split(';').filter { it.isNotEmpty() }.mapNotNull { pair ->
            val equals = pair.indexOf('=')
            if (equals < 0) null else pair.substring(0, equals).trim() to pair.substring(equals + 1).trim()
        }

    /** Pairs back into the stored string */
    fun text(values: Map<String, String>): String =
        options.mapNotNull { option -> values[option.key]?.takeIf { it.isNotEmpty() }?.let { "${option.key}=$it" } }
            .joinToString(";")

    /** The written form of a valid value, or null */
    fun rendered(kind: Kind, value: String): String? = when (kind) {
        is Kind.Choice -> if (value !in kind.allowed) null
            else if (value.all { it in '0'..'9' }) value else "\"$value\""
        is Kind.Number -> {
            val parts = value.removePrefix("-").split('.', limit = 2)
            val plain = parts.all { part -> part.isNotEmpty() && part.all { it in '0'..'9' } }
            val number = value.toDoubleOrNull()
            if (plain && number != null && number >= kind.low && number <= kind.high) value else null
        }
        Kind.Control -> {
            val fine = value.isNotEmpty() && value.length <= 40 &&
                value.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it in " _-" }
            if (fine) "\"$value\"" else null
        }
    }

    fun configContents(context: ServiceContext): String {
        val given = parsed(context.settings.shairportOptions)
        val cec = cecVolume(context).enabled
        val out = StringBuilder()
        for (section in listOf("general", "alsa")) {
            out.append("$section = {\n")
            for (option in options.filter { it.section == section }) {
                val value = if (cec && option.key == "ignore_volume_control") "yes"
                    else given.lastOrNull { it.first == option.key }?.second ?: continue
                val line = rendered(option.kind, value) ?: continue
                out.append("  ${option.key} = $line;\n")
            }
            out.append("};\n")
        }
        if (cec) out.append(METADATA_BLOCK)
        return out.toString()
    }

    private const val METADATA_BLOCK = "metadata = {\n  enabled = \"yes\";\n  include_cover_art = \"no\";\n" +
        "  pipe_name = \"$CEC_PIPE_DIRECTORY/metadata\";\n  pipe_timeout = 5000;\n};\n"
}
