package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The shelf-first question, and what each default costs */
class CategorySelectionTests {
    private fun form(scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET) =
        ConfiguratorForm(scope = scope)

    @Test
    fun `switching a shelf on installs the product the catalog leads with`() {
        val code = ServiceRegistry.categories.first { it.id == "code" }
        val after = CategorySelection.toggleCategory(form(), code, on = true)
        assertEquals(
            listOf(ServiceRegistry.services(code).first().id),
            CategorySelection.selection(after, code),
        )
    }

    /** The switch answers "do I want this at all" */
    @Test
    fun `switching an already-answered shelf on again changes nothing`() {
        val files = ServiceRegistry.categories.first { it.id == "files" }
        val second = ServiceRegistry.services(files)[1].id
        val chosen = CategorySelection.setSelection(form(), files, setOf(second))
        assertEquals(chosen, CategorySelection.toggleCategory(chosen, files, on = true))
    }

    @Test
    fun `switching a shelf off leaves every other shelf alone`() {
        val files = ServiceRegistry.categories.first { it.id == "files" }
        val code = ServiceRegistry.categories.first { it.id == "code" }
        var f = CategorySelection.toggleCategory(form(), files, on = true)
        f = CategorySelection.toggleCategory(f, code, on = true)
        val after = CategorySelection.toggleCategory(f, files, on = false)
        assertTrue(CategorySelection.selection(after, files).isEmpty())
        assertEquals(CategorySelection.selection(f, code), CategorySelection.selection(after, code))
    }

    @Test
    fun `a tunnelled deployment is not offered the VPN shelf`() {
        val available = CategorySelection.available(DeploymentScope.CLOUDFLARE_TUNNEL)
        assertFalse(available.any { it.id == ServiceCategory.VPN.id }, "$available")
        assertTrue(CategorySelection.available(DeploymentScope.PUBLIC_INTERNET)
            .any { it.id == ServiceCategory.VPN.id })
    }

    @Test
    fun `every offered shelf has at least one product this scope can install`() {
        for (scope in DeploymentScope.entries) {
            for (category in CategorySelection.available(scope)) {
                assertTrue(
                    ServiceRegistry.services(category, scope).isNotEmpty(),
                    "$scope offers ${category.id} and can install nothing from it",
                )
            }
        }
    }

    /** VPN keeps its own step: its protocols carry per-protocol fields */
    @Test
    fun `the VPN shelf never opens a picker row`() {
        val f = CategorySelection.toggleCategory(form(), ServiceCategory.VPN, on = true)
        assertTrue(CategorySelection.selection(f, ServiceCategory.VPN).isNotEmpty())
        assertFalse(CategorySelection.offersPicker(f, ServiceCategory.VPN))
    }

    /** A shelf with one member has nothing to pick between */
    @Test
    fun `a single-product shelf opens no picker`() {
        val single = ServiceRegistry.categories.firstOrNull { ServiceRegistry.services(it).size == 1 }
        if (single != null) {
            val f = CategorySelection.toggleCategory(form(), single, on = true)
            assertFalse(CategorySelection.offersPicker(f, single))
        }
    }

    @Test
    fun `the heavy default warns on the row that selected it`() {
        val code = ServiceRegistry.categories.first { it.id == "code" }
        val f = CategorySelection.toggleCategory(form(), code, on = true)
        if (ServiceID.GITLAB in CategorySelection.selection(f, code)) {
            assertEquals(CategorySelection.WarningKey.GITLAB_MEMORY, CategorySelection.warning(f, code))
        }
        val light = CategorySelection.setSelection(
            f, code, setOf(ServiceRegistry.services(code).first { it.id != ServiceID.GITLAB }.id),
        )
        assertNull(CategorySelection.warning(light, code))
    }

    @Test
    fun `Ollama with no model consumer nudges on the row`() {
        val ai = ServiceRegistry.categories.first { it.id == "ai" }
        val alone = CategorySelection.setSelection(form(), ai, setOf(ServiceID.OLLAMA))
        assertEquals(CategorySelection.WarningKey.OLLAMA_NO_UI, CategorySelection.warning(alone, ai))

        val withUI = CategorySelection.setSelection(
            form(), ai, setOf(ServiceID.OLLAMA, ServiceID.OPEN_WEB_UI),
        )
        assertNull(CategorySelection.warning(withUI, ai))

        val uiOnly = CategorySelection.setSelection(form(), ai, setOf(ServiceID.OPEN_WEB_UI))
        assertNull(CategorySelection.warning(uiOnly, ai))
    }

    @Test
    fun `the three products whose choice has a cost carry a note`() {
        assertNotNull(CategorySelection.note(ServiceID.GITLAB))
        assertNotNull(CategorySelection.note(ServiceID.ADGUARD_HOME))
        assertNotNull(CategorySelection.note(ServiceID.PIHOLE))
    }

    @Test
    fun `an empty shelf shows a dash rather than an empty gap`() {
        val files = ServiceRegistry.categories.first { it.id == "files" }
        assertEquals("—", CategorySelection.chosenNames(form(), files))
    }
}
