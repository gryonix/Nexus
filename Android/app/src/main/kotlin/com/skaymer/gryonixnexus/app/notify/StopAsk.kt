package com.skaymer.gryonixnexus.app.notify

/** Two-tap Stop: first tap asks, second stops */
class StopAsk(private val windowMillis: Long = WINDOW_MILLIS) {
    enum class Tap { ASK, STOP }

    private var askedAt: Long? = null

    @Synchronized
    fun isAsking(now: Long): Boolean = askedAt?.let { now - it < windowMillis } == true

    @Synchronized
    fun tap(now: Long): Tap {
        if (isAsking(now)) {
            askedAt = null
            return Tap.STOP
        }
        askedAt = now
        return Tap.ASK
    }

    companion object {
        const val WINDOW_MILLIS = 5_000L
    }
}
