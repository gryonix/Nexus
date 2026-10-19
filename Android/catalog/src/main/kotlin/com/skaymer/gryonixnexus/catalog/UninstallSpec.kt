package com.skaymer.gryonixnexus.catalog

/** How a service is removed from its machine */
data class UninstallSpec(
    val composeProject: String? = null,
    /** Directory holding compose/config files */
    val configDirectory: String? = null,
    val dataPaths: List<String> = emptyList(),
    val backupDirs: List<String> = emptyList(),
    /** Bash run before the compose project goes down (e.g */
    val preSteps: List<String> = emptyList(),
    val postSteps: List<String> = emptyList()
)
