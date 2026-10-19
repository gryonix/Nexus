package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The hub and its add-ons, as rows show them */
class SmartHomeDashboardTest {
    private val context = ServiceContext(
        domain = "example.net",
        sshUser = "root",
        settings = ServiceSettings(homeAssistantUSBDevice = "/dev/ttyACM0"),
    )

    private fun service(id: ServiceID) = assertNotNull(ServiceRegistry.service(id), id.rawValue)

    @Test
    fun `the hub and the bridge have addresses and the broker has none`() {
        assertEquals("home.example.net", ServiceAddress.of(service(ServiceID.HOME_ASSISTANT), context))
        assertEquals("zigbee.example.net", ServiceAddress.of(service(ServiceID.ZIGBEE2MQTT), context))
        assertNull(ServiceAddress.of(service(ServiceID.MOSQUITTO), context))
    }

    @Test
    fun `each smart-home service can be powered, logged, updated and backed up`() {
        for (id in listOf(ServiceID.HOME_ASSISTANT, ServiceID.MOSQUITTO, ServiceID.ZIGBEE2MQTT)) {
            val actions = service(id).actions(context)
            assertNotNull(actions.restart, id.rawValue)
            assertNotNull(actions.logs, id.rawValue)
            assertNotNull(actions.backup, id.rawValue)
            assertNotNull(actions.restore, id.rawValue)
            assertTrue(service(id).updateSpec(context).images.isNotEmpty(), id.rawValue)
        }
    }

    @Test
    fun `the demo scenario B server carries the whole shelf`() {
        val home = DemoDeployments.fleet(requested = 4)
            .firstOrNull { ServiceID.HOME_ASSISTANT in it.services }
        assertNotNull(home, "no demo server carries the hub")
        assertTrue(ServiceID.MOSQUITTO in home.services)
        assertTrue(ServiceID.ZIGBEE2MQTT in home.services)
        assertTrue(home.serviceSettings.homeAssistantUSBDevice.isNotEmpty())
    }
}
