package com.skaymer.gryonixnexus.core

import com.skaymer.gryonixnexus.catalog.Apt

/** Firewall tool */
enum class FirewallTool { NFTABLES, UFW, IPTABLES }

/** A third-party package repository a service is installed from */
data class PackageRepository(
    /** Short identifier used for key/source file names (e.g */
    val name: String,
    val aptGPGKeyURL: String,
    val aptSourceListURL: String
)

internal object AptRepositoryCommand {
    fun render(repository: PackageRepository): String {
        val keyring = "/usr/share/keyrings/${repository.name}-archive-keyring.gpg"
        return "${Apt.QUIET} install -yq --no-install-recommends apt-transport-https curl gnupg\n" +
            "curl -1sLf '${repository.aptGPGKeyURL}' | gpg --dearmor --yes -o $keyring\n" +
            "curl -1sLf '${repository.aptSourceListURL}' > /etc/apt/sources.list.d/${repository.name}.list"
    }
}

interface DistributionProfile {
    val id: DistributionProfileID

    val osReleaseID: String

    /** Human-readable name for error messages */
    val displayName: String
    val firewallTool: FirewallTool

    fun installCommand(packages: List<String>): String
    fun serviceRestartCommand(service: String): String

    fun addRepositoryCommand(repository: PackageRepository): String
}

/** Debian profile (11/12): apt, systemd, nftables */
class DebianProfile : DistributionProfile {
    override val id = DistributionProfileID.DEBIAN
    override val osReleaseID = "debian"
    override val displayName = "Debian"
    override val firewallTool = FirewallTool.NFTABLES

    override fun installCommand(packages: List<String>): String =
        "${Apt.DROP_RETIRED_SOURCES}\n" +
            "${Apt.QUIET} update -q\n" +
            "${Apt.QUIET} install -yq --no-install-recommends " +
            packages.joinToString(" ")

    override fun serviceRestartCommand(service: String): String = "systemctl restart $service"

    override fun addRepositoryCommand(repository: PackageRepository): String =
        AptRepositoryCommand.render(repository)
}

class UbuntuProfile : DistributionProfile {
    override val id = DistributionProfileID.UBUNTU
    override val osReleaseID = "ubuntu"
    override val displayName = "Ubuntu"
    override val firewallTool = FirewallTool.NFTABLES

    override fun installCommand(packages: List<String>): String =
        "${Apt.DROP_RETIRED_SOURCES}\n" +
            "${Apt.QUIET} update -q\n" +
            "${Apt.QUIET} install -yq --no-install-recommends " +
            packages.joinToString(" ")

    override fun serviceRestartCommand(service: String): String = "systemctl restart $service"

    override fun addRepositoryCommand(repository: PackageRepository): String =
        AptRepositoryCommand.render(repository)
}

/** The profile a stored identifier stands for */
fun DistributionProfileID.makeProfile(): DistributionProfile = when (this) {
    DistributionProfileID.DEBIAN -> DebianProfile()
    DistributionProfileID.UBUNTU -> UbuntuProfile()
}

/** Does a host's `/etc/os-release` satisfy a script generated for `expected`? */
object DistributionMatch {
    fun accepts(expected: String, id: String, idLike: String): Boolean {
        if (id == expected) return true
        val supported = DistributionProfileID.entries.map { it.makeProfile().osReleaseID }.toSet()
        if (id in supported) return false
        return idLike.split(" ").any { it == expected }
    }
}
