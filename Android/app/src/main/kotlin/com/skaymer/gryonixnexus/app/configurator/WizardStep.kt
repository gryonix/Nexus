package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceRegistry

enum class WizardStep { SERVICES, VPN_PROTOCOL, DOMAIN, ADDRESS, ADMIN, DNS, REVIEW }

/** The steps this form needs answering, in order */
fun wizardSteps(form: ConfiguratorForm, standingOnVpnStep: Boolean = false): List<WizardStep> {
    val steps = mutableListOf(WizardStep.SERVICES)
    if (hasVpnProtocol(form) || standingOnVpnStep) steps += WizardStep.VPN_PROTOCOL
    if (form.scope.usesInternalTLS && !form.scope.publishesAddressRecords && form.isLocalOnly) {
        steps += WizardStep.ADDRESS
    } else {
        steps += WizardStep.DOMAIN
        steps += WizardStep.ADDRESS
    }
    if (hasAdminService(form)) steps += WizardStep.ADMIN
    if (form.scope.publishesAddressRecords) steps += WizardStep.DNS
    steps += WizardStep.REVIEW
    return steps
}

fun hasVpnProtocol(form: ConfiguratorForm): Boolean =
    ServiceRegistry.services(ServiceCategory.VPN).any { it.id in form.services }

fun hasAdminService(form: ConfiguratorForm): Boolean =
    ServiceRegistry.services(form.services).any { it.usesSharedAdminLogin }
