package com.skaymer.gryonixnexus.core

class Domain private constructor(val name: String) {
    override fun toString(): String = name
    override fun equals(other: Any?): Boolean = other is Domain && other.name == name
    override fun hashCode(): Int = name.hashCode()

    companion object {
        fun of(value: String): Domain {
            val normalized = value.trim().lowercase()
            if (!isValid(normalized)) throw ValidationError.InvalidDomain(value)
            return Domain(normalized)
        }

        fun localOnly(value: String): Domain {
            val normalized = value.trim().lowercase()
            if (!isValid(normalized, allowLocalAddress = true)) {
                throw ValidationError.InvalidDomain(value)
            }
            return Domain(normalized)
        }

        fun isValid(candidate: String): Boolean {
            if (candidate.length > 253) return false
            val labels = candidate.split(".")
            if (labels.size < 2) return false
            for (label in labels) {
                if (label.length !in 1..63) return false
                if (!label.all { it.code < 128 && (it.isLetter() || it.isDigit() || it == '-') }) return false
                if (label.first() == '-' || label.last() == '-') return false
            }
            // TLD: letters only, at least 2 characters.
            val tld = labels.last()
            return tld.length >= 2 && tld.all { it.isLetter() }
        }

        fun isValid(candidate: String, allowLocalAddress: Boolean): Boolean =
            isValid(candidate) || (allowLocalAddress && NetworkAddress.parseOrNull(candidate) != null)
    }
}
