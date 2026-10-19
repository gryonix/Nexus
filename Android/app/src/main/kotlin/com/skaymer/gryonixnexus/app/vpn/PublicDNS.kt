package com.skaymer.gryonixnexus.app.vpn

import androidx.annotation.StringRes
import com.skaymer.gryonixnexus.R
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

/** One public resolver a VPN device can use */
data class PublicDNS(
    val id: String,
    val provider: String,
    @StringRes val variant: Int?,
    val addresses: List<String>,
    @StringRes val blocks: Int,
    val speed: Int,
    val privacy: Int,
    @StringRes val summary: Int,
) {
    companion object {
        private val cloudflare = R.string.dns_summary_cloudflare
        private val adguard = R.string.dns_summary_adguard
        private val dns4eu = R.string.dns_summary_dns4eu
        private val opendns = R.string.dns_summary_opendns

        val all: List<PublicDNS> = listOf(
            PublicDNS("cloudflare", "Cloudflare", null,
                listOf("1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"),
                R.string.dns_blocks_nothing, 3, 3, cloudflare),
            PublicDNS("cloudflare-malware", "Cloudflare", R.string.dns_variant_malware,
                listOf("1.1.1.2", "1.0.0.2", "2606:4700:4700::1112", "2606:4700:4700::1002"),
                R.string.dns_blocks_malware, 3, 3, cloudflare),
            PublicDNS("cloudflare-family", "Cloudflare", R.string.dns_variant_family,
                listOf("1.1.1.3", "1.0.0.3", "2606:4700:4700::1113", "2606:4700:4700::1003"),
                R.string.dns_blocks_adult, 3, 3, cloudflare),
            PublicDNS("google", "Google", null,
                listOf("8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"),
                R.string.dns_blocks_nothing, 3, 1, R.string.dns_summary_google),
            PublicDNS("quad9", "Quad9", null,
                listOf("9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"),
                R.string.dns_blocks_malware, 2, 3, R.string.dns_summary_quad9),
            PublicDNS("adguard", "AdGuard DNS", null,
                listOf("94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"),
                R.string.dns_blocks_ads, 2, 2, adguard),
            PublicDNS("adguard-family", "AdGuard DNS", R.string.dns_variant_family,
                listOf("94.140.14.15", "94.140.15.16", "2a10:50c0::bad1:ff", "2a10:50c0::bad2:ff"),
                R.string.dns_blocks_ads_adult, 2, 2, adguard),
            PublicDNS("dns4eu", "DNS4EU", null,
                listOf("86.54.11.1", "86.54.11.201", "2a13:1001::86:54:11:1", "2a13:1001::86:54:11:201"),
                R.string.dns_blocks_malware, 2, 3, dns4eu),
            PublicDNS("dns4eu-ads", "DNS4EU", R.string.dns_variant_no_ads,
                listOf("86.54.11.13", "86.54.11.213", "2a13:1001::86:54:11:13", "2a13:1001::86:54:11:213"),
                R.string.dns_blocks_ads, 2, 3, dns4eu),
            PublicDNS("dns4eu-child", "DNS4EU", R.string.dns_variant_child,
                listOf("86.54.11.12", "86.54.11.212", "2a13:1001::86:54:11:12", "2a13:1001::86:54:11:212"),
                R.string.dns_blocks_adult, 2, 3, dns4eu),
            PublicDNS("opendns", "OpenDNS", null,
                listOf("208.67.222.222", "208.67.220.220", "2620:119:35::35", "2620:119:53::53"),
                R.string.dns_blocks_nothing, 2, 1, opendns),
            PublicDNS("opendns-family", "OpenDNS", R.string.dns_variant_familyshield,
                listOf("208.67.222.123", "208.67.220.123", "2620:119:35::123", "2620:119:53::123"),
                R.string.dns_blocks_adult, 2, 1, opendns),
        )

        /** The preset these addresses belong to, in any order */
        fun matching(addresses: List<String>): PublicDNS? {
            val wanted = addresses.map { it.lowercase() }.toSet()
            return all.firstOrNull { preset -> preset.addresses.map { it.lowercase() }.toSet() == wanted }
        }

        /** One to four valid addresses, else null */
        fun parse(text: String): List<String>? {
            val parts = text.split(',', ' ', ';', '\n').map { it.trim() }.filter { it.isNotEmpty() }
            if (parts.size !in 1..4) return null
            return parts.takeIf { it.all(::isAddress) }
        }

        private fun isAddress(text: String): Boolean {
            val literal = text.all { it.isDigit() || it == '.' } || (text.contains(':') && text.all { it.isLetterOrDigit() || it == ':' || it == '.' })
            if (!literal) return false
            val parsed = runCatching { InetAddress.getByName(text) }.getOrNull() ?: return false
            return parsed is Inet4Address && text.count { it == '.' } == 3 || parsed is Inet6Address
        }
    }
}
