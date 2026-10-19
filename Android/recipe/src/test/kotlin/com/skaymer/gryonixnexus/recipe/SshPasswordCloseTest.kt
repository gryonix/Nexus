package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `SSHPasswordCloseTests` */
class SshPasswordCloseTest {
    private val appKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFakeFake gryonixnexus-app"

    private fun access(createUser: Boolean) =
        DashboardAccessInput(sshUser = "admin", createUser = createUser, appPublicKey = appKey)

    @Test
    fun `the drop-in outranks cloud-inits`() {
        val name = DashboardAccessSections.PASSWORD_AUTH_DROP_IN_PATH.substringAfterLast('/')
        assertTrue(name < "50-cloud-init.conf", name)
        assertTrue(name < "60-gryonixnexus-tunnel.conf", name)
        assertTrue(name.endsWith(".conf"), "a file the include glob does not match configures nothing")
    }

    @Test
    fun `both password keywords are closed`() {
        val directives = DashboardAccessSections.passwordAuthDropIn
            .lines()
            .filter { !it.startsWith("#") && it.isNotBlank() }
        assertEquals(listOf("PasswordAuthentication no", "KbdInteractiveAuthentication no"), directives)
    }

    /** The body is written from a single-quoted shell literal */
    @Test
    fun `the body cannot end its own shell literal`() {
        assertFalse(DashboardAccessSections.passwordAuthDropIn.contains("'"))
    }

    /** Existing-user mode must not close the door */
    @Test
    fun `existing-user mode closes nothing`() {
        val script = DashboardAccessSections.passwordAuthClose(access(createUser = false), AppLanguage.EN)
        assertEquals(":", script)
    }

    @Test
    fun `the guard looks for the apps own key`() {
        val script = DashboardAccessSections.passwordAuthClose(access(createUser = true), AppLanguage.EN)
        assertTrue(script.contains("""grep -qxF "${'$'}SSHD_APP_KEY" "${'$'}SSHD_KEYS""""), script)
        assertTrue(script.contains("SSHD_APP_KEY='$appKey'"), script)
    }

    @Test
    fun `a rejected configuration is removed again before anything reloads`() {
        val script = DashboardAccessSections.passwordAuthClose(access(createUser = true), AppLanguage.EN)
        val test = script.indexOf("if sshd -t; then")
        val removal = script.indexOf("rm -f '${DashboardAccessSections.PASSWORD_AUTH_DROP_IN_PATH}'")
        val reload = script.indexOf("systemctl reload ssh")
        assertTrue(test in 0 until reload, script)
        assertTrue(test in 0 until removal, script)
        assertFalse(script.contains("systemctl restart ssh"), script)
    }

    @Test
    fun `embedding the body leaves the section indented`() {
        val script = DashboardAccessSections.passwordAuthClose(access(createUser = true), AppLanguage.EN)
        assertTrue(
            script.lines().any { it == "  install -d -m 755 /etc/ssh/sshd_config.d || SSHD_WROTE=0" },
            script,
        )
        assertTrue(script.lines().any { it == "PasswordAuthentication no" }, script)
    }

    /** This section may not take the install down with it */
    @Test
    fun `no step of the close can abort the install`() {
        val script = DashboardAccessSections.passwordAuthClose(access(createUser = true), AppLanguage.EN)
        val staged = DashboardAccessSections.PASSWORD_AUTH_DROP_IN_PATH + ".staged"
        val guarded = listOf(
            "install -d -m 755 /etc/ssh/sshd_config.d || SSHD_WROTE=0",
            "' > '$staged' || SSHD_WROTE=0",
            "chmod 644 '$staged' 2>/dev/null || SSHD_WROTE=0",
            "mv '$staged' '${DashboardAccessSections.PASSWORD_AUTH_DROP_IN_PATH}' 2>/dev/null || SSHD_WROTE=0",
        )
        for (statement in guarded) {
            assertTrue(script.contains(statement), "unguarded under set -e: $statement\n$script")
        }
        assertEquals(guarded.size, script.split("|| SSHD_WROTE=0").size - 1, script)
    }

    @Test
    fun `the script checks that it landed and asks sshd what it resolved`() {
        val script = DashboardAccessSections.passwordAuthClose(access(createUser = true), AppLanguage.EN)
        val landed = script.indexOf("[ ! -f '${DashboardAccessSections.PASSWORD_AUTH_DROP_IN_PATH}' ]")
        val tested = script.indexOf("elif sshd -t; then")
        assertTrue(landed in 0 until tested, "the landing check runs after a test that cannot fail\n$script")

        val reload = script.indexOf("systemctl reload ssh")
        val asked = script.indexOf("sshd -T")
        assertTrue(reload in 0 until asked, "sshd is asked before the reload, so it reads the OLD answer")
        val tail = script.substring(asked)
        assertTrue(tail.contains("passwordauthentication no"), tail)
        assertTrue(tail.contains("kbdinteractiveauthentication no"), tail)
        assertTrue(script.contains("tr 'A-Z' 'a-z'"), script)
    }

    @Test
    fun `the erase takes the drop-in off before stripping the key`() {
        val variant = GoldenFixture.variants.first { it.name.startsWith("A-") && "-access-" in it.name }
        val context = GoldenFixture.context(variant)
        val wrapper = UninstallSections.servicesHostWrapper(
            access(createUser = true), context, includeWireGuard = false
        )
        val removal = wrapper.indexOf("rm -f ${DashboardAccessSections.PASSWORD_AUTH_DROP_IN_PATH}")
        val keyStrip = wrapper.indexOf("""grep -vxF "${'$'}APP_KEY"""")
        assertTrue(removal >= 0, "the erase does not take the drop-in off at all")
        assertTrue(keyStrip >= 0, "the erase no longer strips the app key")
        assertTrue(removal < keyStrip, "the key is stripped before password login comes back")
    }
}
