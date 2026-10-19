package com.skaymer.gryonixnexus.catalog

/** A dollar sign, as a value */
const val SH = "$"

/** Substitutes whole blocks into an already-trimmed template */
fun String.embedding(vararg blocks: Pair<String, String>): String =
    blocks.fold(this) { text, (name, body) -> text.replace("@$name@", body) }
