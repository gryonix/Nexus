package com.skaymer.gryonixnexus.catalog.storage

/** A disk as the app saw it */
data class DiskIdentity(val path: String, val serial: String, val sizeBytes: Long)
