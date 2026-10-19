package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class DemoSecurityTests {
    @Test
    fun `every demo server reads invented protection`() {
        DemoDeployments.fleet(8).forEach { deployment ->
            assertTrue(DemoDeployments.isDemoID(deployment.id), deployment.id)
            assertNotNull(DemoSecurity.status(deployment))
        }
    }

    @Test
    fun `a real server never does`() {
        val real = DemoDeployments.fleet(1).first().copy(id = "B97DA072-8494-4BBA-9C35-55FFE9C27690")
        assertFalse(DemoDeployments.isDemoID(real.id))
        assertNull(DemoSecurity.status(real))
    }
}
