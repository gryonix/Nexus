package com.skaymer.gryonixnexus.core

import com.skaymer.gryonixnexus.catalog.AppLanguage

/** Unified validation error type for display in the UI */
sealed class ValidationError : Exception() {
    data class InvalidDomain(val value: String) : ValidationError()
    data class InvalidHostname(val value: String) : ValidationError()
    data class InvalidAddress(val value: String) : ValidationError()
    data class MissingPublicIP(val role: ServerRole) : ValidationError()
    data class MissingVPNAddress(val role: ServerRole) : ValidationError()
    data class InconsistentTopology(val reason: String) : ValidationError()

    fun message(language: AppLanguage): String = when (this) {
        is InvalidDomain -> L10nValidation.invalidDomain(language, value)
        is InvalidHostname -> L10nValidation.invalidHostname(language, value)
        is InvalidAddress -> L10nValidation.invalidAddress(language, value)
        is MissingPublicIP -> L10nValidation.missingPublicIP(language, role.wireValue)
        is MissingVPNAddress -> L10nValidation.missingVPNAddress(language, role.wireValue)
        is InconsistentTopology -> reason
    }

    /** What `Throwable.message` reports; the English text, as on iOS */
    override val message: String get() = message(AppLanguage.EN)
}
