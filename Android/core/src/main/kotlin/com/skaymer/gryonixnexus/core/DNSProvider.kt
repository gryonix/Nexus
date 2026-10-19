package com.skaymer.gryonixnexus.core

/** Applies DNS records at a specific DNS provider */
interface DNSProvider {
    /** Human-readable provider name for UI/selection */
    val displayName: String

    /** Creates or updates the given records in the provider's zone */
    suspend fun apply(records: List<DNSRecord>, zone: String)
}

data class DNSPublishOutcome(val record: DNSRecord, val result: Result) {
    sealed class Result {
        data object Created : Result()
        data object Updated : Result()

        data object Unchanged : Result()
        data class Failed(val message: String) : Result()
    }
}

interface DNSPublishingProvider : DNSProvider {
    /** Confirms the credential works before anything is written */
    suspend fun verifyToken()

    suspend fun publishReportingOutcomes(records: List<DNSRecord>, zone: String): List<DNSPublishOutcome>

    /** Removes these A records when they point at the address */
    suspend fun removeAddressRecords(names: List<String>, address: String, zone: String): List<String> =
        throw DNSRemovalUnsupported()
}

/** This provider cannot remove records from the app */
class DNSRemovalUnsupported : Exception("removing records is not supported")
