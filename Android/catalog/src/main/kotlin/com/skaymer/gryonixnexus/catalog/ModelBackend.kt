package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class ModelBackend {
    /** On this machine, in a local engine this catalog installs */
    @SerialName("here")
    HERE,

    @SerialName("home")
    HOME,

    /** Nowhere here: the services call somebody else's API */
    @SerialName("external")
    EXTERNAL;

    /** True when the deployment runs an engine of its own */
    val runsLocalEngine: Boolean get() = this != EXTERNAL
}
