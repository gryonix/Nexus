package com.skaymer.gryonixnexus.transport

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LanBannerTest {
    @Test
    fun onlyAnSshGreetingCounts() {
        assertTrue(SSHJCommandRunner.isSSHBanner("SSH-".toByteArray()))
        assertFalse(SSHJCommandRunner.isSSHBanner("HTTP".toByteArray()))
        assertFalse(SSHJCommandRunner.isSSHBanner(ByteArray(0)))
    }
}
