package com.skaymer.gryonixnexus.catalog

data class UpdateSpec(
    val images: List<String>,
    val flavour: Flavour = Flavour.COMPOSE_PULL
) {
    /** How the update is actually applied once one is found */
    enum class Flavour {
        /** `docker compose pull` + `up -d` for the service's own project */
        COMPOSE_PULL,

        OWN_UPDATER,

        BUILT_ON_SERVER
    }

    companion object {
        /** The updater-driven flavour, which names no images by design */
        val OWN_UPDATER = UpdateSpec(images = emptyList(), flavour = Flavour.OWN_UPDATER)

        fun builtOnServer(images: List<String>): UpdateSpec =
            UpdateSpec(images = images, flavour = Flavour.BUILT_ON_SERVER)
    }
}

/** What the app knows about one service's updates */
sealed class ServiceUpdateStatus {
    data object Current : ServiceUpdateStatus()

    /** At least one image behind this service has moved */
    data class Available(val images: List<String>) : ServiceUpdateStatus()

    data object SelfManaged : ServiceUpdateStatus()

    data object RebuiltBySetup : ServiceUpdateStatus()

    /** The check did not produce an answer */
    data object Unknown : ServiceUpdateStatus()
}
