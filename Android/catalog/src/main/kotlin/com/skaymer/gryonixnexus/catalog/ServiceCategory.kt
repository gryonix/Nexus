package com.skaymer.gryonixnexus.catalog

data class ServiceCategory(
    /** Stable identifier, used as the storage key and never shown */
    val id: String,
    val title: String,
    val summary: String,
    val systemImage: String,
    val selection: Selection,
    /** Position in the forms */
    val order: Int
) : Comparable<ServiceCategory> {
    /** How many members may be installed side by side */
    enum class Selection {
        EXCLUSIVE,

        PREFER_ONE,

        MULTIPLE
    }

    override fun compareTo(other: ServiceCategory): Int =
        compareValuesBy(this, other, { it.order }, { it.id })

    companion object {
        /** The domain's mail engine */
        val MAIL = ServiceCategory(
            id = "mail", title = "Mail",
            summary = "A mail server on your own domain: mailboxes, webmail, spam filtering.",
            systemImage = "envelope",
            selection = Selection.EXCLUSIVE, order = 0)

        /** Password managers for people */
        val PASSWORDS = ServiceCategory(
            id = "passwords", title = "Passwords",
            summary = "A password vault for people, with apps and browser extensions.",
            systemImage = "key",
            selection = Selection.PREFER_ONE, order = 1)

        val SECRETS = ServiceCategory(
            id = "secrets", title = "Keys & certificates",
            summary = "Secrets for machines rather than people: API tokens, internal TLS, SSH certificates.",
            systemImage = "lock.shield",
            selection = Selection.MULTIPLE, order = 2)

        /** File sync and storage */
        val FILES = ServiceCategory(
            id = "files", title = "Files",
            summary = "File sync and sharing across your devices — your own drive, on your own server.",
            systemImage = "folder",
            selection = Selection.PREFER_ONE, order = 3)

        val PHOTOS = ServiceCategory(
            id = "photos", title = "Photos",
            summary = "A photo and video library: automatic phone backup, albums, search.",
            systemImage = "photo",
            selection = Selection.PREFER_ONE, order = 4)

        val MEDIA = ServiceCategory(
            id = "media", title = "Media",
            summary = "Streams films, series and music you already own to any device.",
            systemImage = "play.rectangle",
            selection = Selection.MULTIPLE, order = 5)

        /** Git hosting */
        val CODE = ServiceCategory(
            id = "code", title = "Git hosting",
            summary = "Your own Git server: repositories, issues, pull requests.",
            systemImage = "chevron.left.forwardslash.chevron.right",
            selection = Selection.PREFER_ONE, order = 6)

        /** DNS filtering */
        val NETWORK = ServiceCategory(
            id = "network", title = "Ad & tracker blocking",
            summary = "A DNS server for your devices that drops ads, trackers and malware domains before they load.",
            systemImage = "network",
            selection = Selection.EXCLUSIVE, order = 7)

        /** VPN protocols */
        val VPN = ServiceCategory(
            id = "vpn", title = "VPN",
            summary = "An encrypted tunnel into this server from anywhere, with a panel that hands out client profiles.",
            systemImage = "lock.shield",
            selection = Selection.MULTIPLE, order = 8)

        val MESH = ServiceCategory(
            id = "mesh", title = "Private network for your devices",
            summary = "Links your own phones, laptops and servers straight to each other, wherever they are. Nothing is published to the internet.",
            systemImage = "point.3.filled.connected.trianglepath.dotted",
            selection = Selection.PREFER_ONE, order = 9)

        /** Reaching this server from outside WITHOUT opening a port */
        val REMOTE_ACCESS = ServiceCategory(
            id = "remote-access", title = "Access without opening ports",
            summary = "The server dials out and keeps the connection open, so its sites work from the internet even behind a router with no public IP.",
            systemImage = "cloud",
            selection = Selection.PREFER_ONE, order = 10)

        /** One page that links to everything else on this server */
        val DASHBOARD = ServiceCategory(
            id = "dashboard", title = "Start page",
            summary = "One page linking to everything installed on this server, built from the services you picked.",
            systemImage = "square.grid.2x2",
            selection = Selection.PREFER_ONE, order = 11)

        /** One login in front of the admin panels */
        val SINGLE_SIGN_ON = ServiceCategory(
            id = "sso", title = "Single sign-on",
            summary = "One login in front of the admin panels, on top of the password each of them already has.",
            systemImage = "person.badge.key",
            selection = Selection.PREFER_ONE, order = 12)

        /** Game servers people invite friends to */
        val GAMES = ServiceCategory(
            id = "games", title = "Game servers",
            summary = "A Minecraft server on your own machine, with a web panel for the console, players and backups.",
            systemImage = "gamecontroller",
            selection = Selection.MULTIPLE, order = 13)

        val AI = ServiceCategory(
            id = "ai", title = "AI",
            summary = "A model that runs on your own machine, and a chat in front of it: nothing you type, and none of the documents you feed it, leaves the server.",
            systemImage = "brain",
            selection = Selection.MULTIPLE, order = -1)

        val AUTOMATION = ServiceCategory(
            id = "automation", title = "Automation",
            summary = "Connects your services to each other: an event, then a step, then a step. Zapier, running on your own server.",
            systemImage = "arrow.triangle.branch",
            selection = Selection.PREFER_ONE, order = 15)

        val SMART_HOME = ServiceCategory(
            id = "smart-home", title = "Smart home",
            summary = "Runs the house from your own machine: lights, sensors, heating and cameras in one app, working even when the internet is down. Only on a machine at home.",
            systemImage = "house",
            selection = Selection.MULTIPLE, order = 16)

        val IMPLICIT = ServiceCategory(
            id = "implicit", title = "", summary = "", systemImage = "gearshape",
            selection = Selection.MULTIPLE, order = 99)

        /** Every category, in the order the forms show them */
        val SELECTABLE: List<ServiceCategory> = listOf(
            MAIL, PASSWORDS, SECRETS, FILES, PHOTOS, MEDIA, CODE, NETWORK, VPN, MESH,
            REMOTE_ACCESS, DASHBOARD, SINGLE_SIGN_ON, GAMES, AI, AUTOMATION, SMART_HOME
        )
    }
}
