package com.skaymer.gryonixnexus.app.configurator

import androidx.annotation.StringRes
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.core.CloudflareDNSProvider
import com.skaymer.gryonixnexus.core.DNSPublishingProvider
import com.skaymer.gryonixnexus.core.DigitalOceanDNSProvider
import com.skaymer.gryonixnexus.core.GoDaddyDNSProvider
import com.skaymer.gryonixnexus.core.GoogleCloudDNSProvider
import com.skaymer.gryonixnexus.core.HetznerDNSProvider
import com.skaymer.gryonixnexus.core.OVHDNSProvider
import com.skaymer.gryonixnexus.core.PorkbunDNSProvider
import com.skaymer.gryonixnexus.core.Route53DNSProvider

enum class DNSProviderKind {
    CLOUDFLARE,
    DIGITALOCEAN,
    HETZNER,
    PORKBUN,
    OVH,
    ROUTE53,
    GOOGLE_CLOUD,
    GODADDY;

    /** Not localized — a brand name, the same way `CloudflareDNSProvider.displayName` is */
    val displayName: String
        get() = when (this) {
            CLOUDFLARE -> "Cloudflare"
            DIGITALOCEAN -> "DigitalOcean"
            HETZNER -> "Hetzner"
            PORKBUN -> "Porkbun"
            OVH -> "OVHcloud"
            ROUTE53 -> "Amazon Route 53"
            GOOGLE_CLOUD -> "Google Cloud DNS"
            GODADDY -> "GoDaddy"
        }

    @get:StringRes
    val tokenLabelRes: Int
        get() = when (this) {
            CLOUDFLARE, DIGITALOCEAN, HETZNER, PORKBUN, OVH, ROUTE53, GOOGLE_CLOUD, GODADDY ->
                R.string.wizard_publish_token
        }

    @get:StringRes
    val publishButtonRes: Int
        get() = when (this) {
            CLOUDFLARE, DIGITALOCEAN, HETZNER, PORKBUN, OVH, ROUTE53, GOOGLE_CLOUD, GODADDY ->
                R.string.wizard_publish_button
        }

    @get:StringRes
    val setupHintRes: Int
        get() = when (this) {
            CLOUDFLARE -> R.string.wizard_publish_footer
            DIGITALOCEAN -> R.string.wizard_publish_footer_digitalocean
            HETZNER -> R.string.wizard_publish_footer_hetzner
            PORKBUN -> R.string.wizard_publish_footer_porkbun
            OVH -> R.string.wizard_publish_footer_ovh
            ROUTE53 -> R.string.wizard_publish_footer_route53
            GOOGLE_CLOUD -> R.string.wizard_publish_footer_googlecloud
            GODADDY -> R.string.wizard_publish_footer_godaddy
        }

    fun makeProvider(token: String): DNSPublishingProvider = when (this) {
        CLOUDFLARE -> CloudflareDNSProvider(token)
        DIGITALOCEAN -> DigitalOceanDNSProvider(token)
        HETZNER -> HetznerDNSProvider(token)
        PORKBUN -> PorkbunDNSProvider(token)
        OVH -> OVHDNSProvider(token)
        ROUTE53 -> Route53DNSProvider(token)
        GOOGLE_CLOUD -> GoogleCloudDNSProvider(token)
        GODADDY -> GoDaddyDNSProvider(token)
    }
}
