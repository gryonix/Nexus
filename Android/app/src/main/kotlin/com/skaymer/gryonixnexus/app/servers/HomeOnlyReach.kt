package com.skaymer.gryonixnexus.app.servers

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/** Whether a home-only site opens from here */
enum class HomeOnlyReach {
    CHECKING, OPENS, CLOSED_HERE;

    companion object {
        /** A guard refusal or no answer means not from here */
        suspend fun check(host: String): HomeOnlyReach = withContext(Dispatchers.IO) {
            runCatching {
                val connection = URL("https://$host/").openConnection() as HttpURLConnection
                connection.requestMethod = "HEAD"
                connection.connectTimeout = 4000
                connection.readTimeout = 4000
                try {
                    if (connection.responseCode == 403) CLOSED_HERE else OPENS
                } finally {
                    connection.disconnect()
                }
            }.getOrDefault(CLOSED_HERE)
        }
    }
}
