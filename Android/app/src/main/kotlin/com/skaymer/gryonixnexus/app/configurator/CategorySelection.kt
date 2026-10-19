package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry

object CategorySelection {
    /** The shelves this deployment may choose from */
    fun available(scope: DeploymentScope): List<ServiceCategory> {
        if (scope.carriesNonWebServices) return ServiceRegistry.categories
        return ServiceRegistry.categories.filter { category ->
            category.id != ServiceCategory.VPN.id &&
                ServiceRegistry.services(category).any { !it.requiresPublicDomain }
        }
    }

    fun selection(form: ConfiguratorForm, category: ServiceCategory): List<ServiceID> =
        ServiceRegistry.services(category).map { it.id }.filter { it in form.services }

    fun defaultMember(category: ServiceCategory, scope: DeploymentScope): ServiceID? =
        ServiceRegistry.services(category, scope).firstOrNull()?.id

    /** Turn a whole shelf on or off */
    fun toggleCategory(
        form: ConfiguratorForm,
        category: ServiceCategory,
        on: Boolean,
    ): ConfiguratorForm {
        val members = ServiceRegistry.services(category).map { it.id }.toSet()
        if (!on) return form.copy(services = form.services - members)
        if (selection(form, category).isNotEmpty()) return form
        val fallback = defaultMember(category, form.scope) ?: return form
        return form.copy(services = form.services + fallback)
    }

    /** Replace what one shelf installs, leaving every other shelf alone */
    fun setSelection(
        form: ConfiguratorForm,
        category: ServiceCategory,
        ids: Set<ServiceID>,
    ): ConfiguratorForm {
        val members = ServiceRegistry.services(category).map { it.id }.toSet()
        return form.copy(services = form.services - members + ids.intersect(members))
    }

    /** Whether the shelf's row opens a picker */
    fun offersPicker(form: ConfiguratorForm, category: ServiceCategory): Boolean =
        category.id != ServiceCategory.VPN.id &&
            ServiceRegistry.services(category).size > 1 &&
            selection(form, category).isNotEmpty()

    fun chosenNames(form: ConfiguratorForm, category: ServiceCategory): String {
        val names = ServiceRegistry.services(category)
            .filter { it.id in form.services }
            .map { it.displayName }
        return if (names.isEmpty()) "—" else names.joinToString(", ")
    }

    fun warning(form: ConfiguratorForm, category: ServiceCategory): WarningKey? {
        val selected = selection(form, category)
        return when {
            ServiceID.GITLAB in selected -> WarningKey.GITLAB_MEMORY
            ServiceID.OLLAMA in selected &&
                selected.none { it in ServiceID.MODEL_CONSUMERS } -> WarningKey.OLLAMA_NO_UI
            else -> null
        }
    }

    fun note(id: ServiceID): NoteKey? = when (id) {
        ServiceID.GITLAB -> NoteKey.GITLAB
        ServiceID.ADGUARD_HOME -> NoteKey.ADGUARD
        ServiceID.PIHOLE -> NoteKey.PIHOLE
        else -> null
    }

    enum class WarningKey { GITLAB_MEMORY, OLLAMA_NO_UI }

    enum class NoteKey { GITLAB, ADGUARD, PIHOLE }
}
