package com.skaymer.gryonixnexus.servercontrol

/** Downsampling levels the server-side collector maintains */
enum class MetricsHistoryBucket(val rawValue: String) {
    TEN_SECONDS("10s"),
    ONE_MINUTE("1m"),
    TEN_MINUTES("10m"),
    ONE_HOUR("1h"),
    ONE_DAY("1d"),
    ONE_WEEK("1w");

    /** Seconds between two points of this bucket */
    val pointInterval: Double
        get() = when (this) {
            TEN_SECONDS -> 10.0
            ONE_MINUTE -> 60.0
            TEN_MINUTES -> 600.0
            ONE_HOUR -> 3_600.0
            ONE_DAY -> 86_400.0
            ONE_WEEK -> 604_800.0
        }

    companion object {
        fun fromRawValue(raw: String): MetricsHistoryBucket? = entries.find { it.rawValue == raw }
    }
}
