package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.core.DNSPublishOutcome

object DNSPublishSummary {
    data class Result(val lines: List<String>, val failed: Boolean)

    fun summarize(zone: String, outcomes: List<DNSPublishOutcome>): Result {
        var created = 0
        var updated = 0
        var unchanged = 0
        var failed = false
        val problems = mutableListOf<String>()
        outcomes.forEach { outcome ->
            when (val result = outcome.result) {
                is DNSPublishOutcome.Result.Created -> created += 1
                is DNSPublishOutcome.Result.Updated -> updated += 1
                is DNSPublishOutcome.Result.Unchanged -> unchanged += 1
                is DNSPublishOutcome.Result.Failed -> {
                    failed = true
                    problems += "${outcome.record.name}: ${result.message}"
                }
            }
        }
        val head = "$zone: $created added, $updated updated, $unchanged already correct."
        return Result(listOf(head) + problems, failed)
    }
}
