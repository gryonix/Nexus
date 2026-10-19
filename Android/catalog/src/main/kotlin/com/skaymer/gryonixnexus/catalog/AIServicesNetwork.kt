package com.skaymer.gryonixnexus.catalog

/** The Docker network the AI services reach each other on */
object AIServicesNetwork {
    /** External, so removing one service leaves it to the rest */
    const val NAME = "gryonixnexus-ai"

    /** A neighbour's address on the shared network */
    fun url(container: String, port: Int): String = "http://$container:$port"

    /** Joins a service to the network; ends its compose file */
    const val COMPOSE_TAIL = "\n    networks:\n      - $NAME\nnetworks:\n  $NAME:\n    external: true"

    /** Creates the network once; later runs find it there */
    const val CREATE_STEP = "docker network create $NAME >/dev/null 2>&1 || true"
}
