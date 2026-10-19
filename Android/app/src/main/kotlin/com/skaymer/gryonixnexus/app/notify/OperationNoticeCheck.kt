package com.skaymer.gryonixnexus.app.notify

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import com.skaymer.gryonixnexus.R
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.delay

/** A sample operation notice, only in debug builds */
object OperationNoticeCheck {
    const val STEPS = 6
    const val STEP_MILLIS = 5_000L
    private val running = AtomicBoolean(false)

    /** Debug builds only; release builds never offer it */
    fun isOffered(context: Context): Boolean =
        context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    fun run(context: Context) {
        if (!isOffered(context) || !running.compareAndSet(false, true)) return
        val title = context.getString(R.string.operations_test_title)
        val notice = OperationNotices.startTitled(title, Build.MODEL ?: "Android", step(context, 1))
        OperationNotices.launch {
            try {
                for (number in 2..STEPS) {
                    delay(STEP_MILLIS)
                    notice.update(step(context, number), number.toDouble() / STEPS)
                }
                delay(STEP_MILLIS)
                notice.finish(step(context, STEPS))
            } finally {
                running.set(false)
            }
        }
    }

    private fun step(context: Context, number: Int): String =
        context.getString(R.string.operations_test_step, number, STEPS)
}
