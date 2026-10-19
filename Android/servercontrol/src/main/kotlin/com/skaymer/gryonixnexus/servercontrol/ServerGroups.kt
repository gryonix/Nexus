package com.skaymer.gryonixnexus.servercontrol

object ServerGroups {
    fun known(deployments: List<Deployment>): List<String> =
        deployments.flatMap { it.tags }.toSet().sorted()

    fun setting(member: Boolean, group: String, tags: List<String>): List<String> {
        val result = tags.filterNot { it.equals(group, ignoreCase = true) }
        return if (member) result + group else result
    }

    /** Every server that carries this group */
    fun members(group: String, deployments: List<Deployment>): List<Deployment> =
        deployments.filter { deployment ->
            deployment.tags.any { it.equals(group, ignoreCase = true) }
        }

    fun clean(raw: String): String? = raw.trim().ifEmpty { null }

    fun reachable(selection: String?, deployments: List<Deployment>): String? =
        if (selection == null || known(deployments).contains(selection)) selection else null
}
