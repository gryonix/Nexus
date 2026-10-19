package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class AgentInstallSettingsTest {
    @Test
    fun `every declared key is produced and nothing else is`() {
        val produced = AgentInstallSettings.map(ServiceSettings()).keys
        assertEquals(AgentInstallSettings.keys, produced)
        assertFalse(
            AgentInstallSettings.VPN_PROTOCOLS_KEY in produced,
            "vpn_protocols says WHAT to install, not how — it rides on the request",
        )
    }

    /** The whole deployment's knobs, not one service's */
    @Test
    fun `moved paths travel for services that are not being installed`() {
        val map = AgentInstallSettings.map(
            ServiceSettings(
                nextcloudPath = "/srv/nextcloud",
                jellyfinMediaPath = "/mnt/films",
                xrayRealitySNI = "www.cloudflare.com",
            ),
        )
        assertEquals("/srv/nextcloud", map["nextcloud_path"])
        assertEquals("/mnt/films", map["jellyfin_media_path"])
        assertEquals("www.cloudflare.com", map["xray_reality_sni"])
    }

    @Test
    fun `flags and ports are sent in the form the agent parses`() {
        val map = AgentInstallSettings.map(
            ServiceSettings(
                vaultwardenAllowSignups = false,
                xrayRealityPort = 9443,
                forgejoSSHPort = 0,
            ),
        )
        assertEquals("false", map["vaultwarden_allow_signups"])
        assertEquals("9443", map["xray_reality_port"])
        assertEquals("0", map["forgejo_ssh_port"])
    }

    /** The protected-service list is in CATALOG order, not set order */
    @Test
    fun `protected services travel in catalog order not set order`() {
        val map = AgentInstallSettings.map(
            ServiceSettings(
                autheliaProtectedServices = setOf(
                    ServiceID.ADGUARD_HOME,
                    ServiceID.NEXTCLOUD,
                    ServiceID.VAULTWARDEN,
                    ServiceID.IMMICH,
                ),
            ),
        )
        assertEquals("vaultwarden,nextcloud,immich,adguard-home", map["authelia_protected_services"])
    }

    /** Nothing protected is an empty value, not a missing key */
    @Test
    fun `an empty protected set still sends the key`() {
        val map = AgentInstallSettings.map(ServiceSettings(autheliaProtectedServices = emptySet()))
        assertEquals("", map["authelia_protected_services"])
    }

    @Test
    fun `adding a protocol keeps the ones already installed`() {
        val installed = setOf(ServiceID.WIREGUARD_VPN, ServiceID.VPN_PANEL, ServiceID.NEXTCLOUD)
        assertEquals(
            "wireguard-vpn,openvpn",
            AgentInstallSettings.vpnProtocolList(ServiceID.OPEN_VPN, installed),
        )
    }

    @Test
    fun `the list follows the catalog's order`() {
        val installed = setOf(ServiceID.OPEN_VPN, ServiceID.SHADOWSOCKS)
        assertEquals(
            "wireguard-vpn,shadowsocks,openvpn",
            AgentInstallSettings.vpnProtocolList(ServiceID.WIREGUARD_VPN, installed),
        )
    }

    /**
     * Anything that is not a VPN piece has no protocol list at all — the key
     * must not appear on an ordinary install.
     */
    @Test
    fun `a non-VPN service gets no protocol list`() {
        assertNull(AgentInstallSettings.vpnProtocolList(ServiceID.NEXTCLOUD, setOf(ServiceID.WIREGUARD_VPN)))
        assertNull(AgentInstallSettings.vpnProtocolList(ServiceID.JELLYFIN, emptySet()))
    }

    /**
     * Not in the Swift twin, and it is the reason the panel key exists at all:
     * installing the PANEL on a host that already runs protocols must keep every
     * one of them, and installing it on a host with none has nothing to say.
     */
    @Test
    fun `installing the panel keeps the protocols already there and adds none`() {
        assertEquals(
            "wireguard-vpn,openvpn",
            AgentInstallSettings.vpnProtocolList(
                ServiceID.VPN_PANEL,
                setOf(ServiceID.WIREGUARD_VPN, ServiceID.OPEN_VPN),
            ),
        )
        assertNull(AgentInstallSettings.vpnProtocolList(ServiceID.VPN_PANEL, emptySet()))
    }
}
