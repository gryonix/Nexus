package com.skaymer.gryonixnexus.app.notify

import kotlinx.serialization.json.JsonObject

/** What a tap on a server alert opens */
data class AlertTap(val jobID: String?, val destination: AlertDestination?, val card: AlertCard?) {
    companion object {
        fun of(gnx: JsonObject?, title: String?, body: String?, deploymentID: (String) -> String?): AlertTap =
            AlertTap(
                jobID = AlertDestination.jobID(gnx),
                destination = AlertDestination.from(gnx, deploymentID),
                card = AlertCard.from(AlertDestination.kind(gnx), title, body),
            )
    }
}
