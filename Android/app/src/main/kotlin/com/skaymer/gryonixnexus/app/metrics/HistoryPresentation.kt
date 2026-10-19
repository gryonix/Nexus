package com.skaymer.gryonixnexus.app.metrics

object HistoryPresentation {
    /** The same key the other app writes */
    const val INLINE_KEY = "metrics.historyInline"

    fun inline(stored: Boolean?): Boolean = stored ?: false
}
