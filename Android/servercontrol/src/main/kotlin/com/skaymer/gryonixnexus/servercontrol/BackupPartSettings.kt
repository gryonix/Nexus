package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.BackupPart

/** Which parts regular and pre-update backups copy */
data class BackupPartChoice(
    /** Scheduled runs and the backup button */
    val regular: Set<BackupPart> = DEFAULT_REGULAR,
    /** The backup an update takes first */
    val beforeUpdate: Set<BackupPart> = DEFAULT_BEFORE_UPDATE,
) {
    companion object {
        val DEFAULT_REGULAR: Set<BackupPart> = BackupPart.entries.toSet()
        val DEFAULT_BEFORE_UPDATE: Set<BackupPart> = setOf(BackupPart.SETTINGS, BackupPart.DATABASES)
    }
}

/** Which kind of backup a choice is about */
enum class BackupPartScope { REGULAR, BEFORE_UPDATE }

/** The parts one kind of backup copies */
operator fun BackupPartChoice.get(scope: BackupPartScope): Set<BackupPart> =
    if (scope == BackupPartScope.REGULAR) regular else beforeUpdate

fun BackupPartChoice.with(scope: BackupPartScope, parts: Set<BackupPart>): BackupPartChoice =
    if (scope == BackupPartScope.REGULAR) copy(regular = parts) else copy(beforeUpdate = parts)

/** The choice read back from the server */
data class BackupPartsState(
    /** The shared choice, for services without their own */
    val choice: BackupPartChoice = BackupPartChoice(),
    /** False when the server's wrapper predates parts */
    val supported: Boolean = true,
    /** Services with their own choice, by catalog id */
    val services: Map<String, BackupPartChoice> = emptyMap(),
) {
    /** What one service copies */
    fun choiceFor(service: String): BackupPartChoice = services[service] ?: choice

    /** On when shared and every listed service have it */
    fun sharedIsOn(part: BackupPart, scope: BackupPartScope, listed: List<String>): Boolean =
        part in choice[scope] && listed.all { part in choiceFor(it)[scope] }

    /** Turning a shared switch sets it for every listed service */
    fun settingShared(part: BackupPart, scope: BackupPartScope, on: Boolean, listed: List<String>): BackupPartsChange =
        BackupPartsChange(
            shared = choice.with(scope, toggled(choice[scope], part, on)),
            services = listed.associateWith { choiceFor(it).let { own -> own.with(scope, toggled(own[scope], part, on)) } },
        )

    /** One service's switch, leaving the rest as they are */
    fun settingService(service: String, part: BackupPart, scope: BackupPartScope, on: Boolean): BackupPartsChange {
        val own = choiceFor(service)
        return BackupPartsChange(shared = null, services = mapOf(service to own.with(scope, toggled(own[scope], part, on))))
    }

    /** The state with a change applied */
    fun applying(change: BackupPartsChange): BackupPartsState =
        copy(choice = change.shared ?: choice, services = services + change.services)

    private fun toggled(parts: Set<BackupPart>, part: BackupPart, on: Boolean): Set<BackupPart> =
        if (on) parts + part else parts - part
}

/** What to write: the shared choice and services' own */
data class BackupPartsChange(
    val shared: BackupPartChoice?,
    val services: Map<String, BackupPartChoice> = emptyMap(),
)

object BackupPartsParsing {
    /** Parts in the wrapper's own order */
    fun words(parts: Set<BackupPart>): List<String> = BackupPart.entries.filter { it in parts }.map { it.rawValue }

    /** Reads `show-parts` output */
    fun parse(output: String): BackupPartChoice = state(output).choice

    /** Reads `show-parts` output, services' own lines too */
    fun state(output: String): BackupPartsState {
        var choice = BackupPartChoice()
        val own = mutableMapOf<String, MutableMap<BackupPartScope, Set<BackupPart>>>()
        for (line in output.lines()) {
            val pair = line.split("=", limit = 2)
            if (pair.size != 2) continue
            val parts = pair[1].trim('\'', '"', ' ').split(" ").mapNotNull { BackupPart.from(it) }.toSet()
            when (pair[0]) {
                "BACKUP_PARTS" -> choice = choice.copy(regular = parts)
                "UPDATE_PARTS" -> choice = choice.copy(beforeUpdate = parts)
                else -> serviceKey(pair[0])?.let { (service, scope) -> own.getOrPut(service) { mutableMapOf() }[scope] = parts }
            }
        }
        val services = own.mapValues { (_, scopes) ->
            BackupPartChoice(
                regular = scopes[BackupPartScope.REGULAR] ?: choice.regular,
                beforeUpdate = scopes[BackupPartScope.BEFORE_UPDATE] ?: choice.beforeUpdate,
            )
        }
        return BackupPartsState(choice = choice, services = services)
    }

    /** A service id and scope from a config key */
    internal fun serviceKey(key: String): Pair<String, BackupPartScope>? {
        val (prefix, scope) = listOf("BACKUP_PARTS_" to BackupPartScope.REGULAR, "UPDATE_PARTS_" to BackupPartScope.BEFORE_UPDATE)
            .firstOrNull { key.startsWith(it.first) } ?: return null
        val name = key.removePrefix(prefix)
        if (name.isEmpty() || !name.all { it.isLowerCase() || it.isDigit() || it == '_' }) return null
        return name.replace('_', '-') to scope
    }
}
