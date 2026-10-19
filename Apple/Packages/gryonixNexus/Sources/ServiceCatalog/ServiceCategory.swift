public struct ServiceCategory: Sendable, Hashable, Identifiable, Comparable {
    /// How many members may be installed side by side
    public enum Selection: Sendable, Hashable {
        case exclusive
        case preferOne
        case multiple
    }

    /// Stable identifier, used as the storage key and never shown
    public let id: String
    public let title: String
    public let summary: String
    public let systemImage: String
    public let selection: Selection
    /// Position in the forms
    public let order: Int

    public init(id: String, title: String, summary: String, systemImage: String,
                selection: Selection, order: Int) {
        self.id = id
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.selection = selection
        self.order = order
    }

    public static func < (lhs: ServiceCategory, rhs: ServiceCategory) -> Bool {
        (lhs.order, lhs.id) < (rhs.order, rhs.id)
    }
}

extension ServiceCategory {
    /// The domain's mail engine
    public static let mail = ServiceCategory(
        id: "mail", title: "Mail",
        summary: "A mail server on your own domain: mailboxes, webmail, spam filtering.",
        systemImage: "envelope",
        selection: .exclusive, order: 0)

    /// Password managers for people
    public static let passwords = ServiceCategory(
        id: "passwords", title: "Passwords",
        summary: "A password vault for people, with apps and browser extensions.",
        systemImage: "key",
        selection: .preferOne, order: 1)

    public static let secrets = ServiceCategory(
        id: "secrets", title: "Keys & certificates",
        summary: "Secrets for machines rather than people: API tokens, internal TLS, SSH certificates.",
        systemImage: "lock.shield",
        selection: .multiple, order: 2)

    /// File sync and storage
    public static let files = ServiceCategory(
        id: "files", title: "Files",
        summary: "File sync and sharing across your devices — your own drive, on your own server.",
        systemImage: "folder",
        selection: .preferOne, order: 3)

    public static let photos = ServiceCategory(
        id: "photos", title: "Photos",
        summary: "A photo and video library: automatic phone backup, albums, search.",
        systemImage: "photo",
        selection: .preferOne, order: 4)

    public static let media = ServiceCategory(
        id: "media", title: "Media",
        summary: "Streams films, series and music you already own to any device.",
        systemImage: "play.rectangle",
        selection: .multiple, order: 5)

    /// Git hosting
    public static let code = ServiceCategory(
        id: "code", title: "Git hosting",
        summary: "Your own Git server: repositories, issues, pull requests.",
        systemImage: "chevron.left.forwardslash.chevron.right",
        selection: .preferOne, order: 6)

    /// DNS filtering
    public static let network = ServiceCategory(
        id: "network", title: "Ad & tracker blocking",
        summary: "A DNS server for your devices that drops ads, trackers and malware domains before they load.",
        systemImage: "network",
        selection: .exclusive, order: 7)

    /// Reaching this server from outside WITHOUT opening a port
    public static let remoteAccess = ServiceCategory(
        id: "remote-access", title: "Access without opening ports",
        summary: "The server dials out and keeps the connection open, so its sites work from the internet even behind a router with no public IP.",
        systemImage: "cloud",
        selection: .preferOne, order: 10)

    public static let mesh = ServiceCategory(
        id: "mesh", title: "Private network for your devices",
        summary: "Links your own phones, laptops and servers straight to each other, wherever they are. Nothing is published to the internet.",
        systemImage: "point.3.filled.connected.trianglepath.dotted",
        selection: .preferOne, order: 9)

    /// VPN protocols
    public static let vpn = ServiceCategory(
        id: "vpn", title: "VPN",
        summary: "An encrypted tunnel into this server from anywhere, with a panel that hands out client profiles.",
        systemImage: "lock.shield",
        selection: .multiple, order: 8)

    /// One login in front of the admin panels
    public static let singleSignOn = ServiceCategory(
        id: "sso", title: "Single sign-on",
        summary: "One login in front of the admin panels, on top of the password each of them already has.",
        systemImage: "person.badge.key",
        selection: .preferOne, order: 12)

    /// One page that links to everything else on this server
    public static let dashboard = ServiceCategory(
        id: "dashboard", title: "Start page",
        summary: "One page linking to everything installed on this server, built from the services you picked.",
        systemImage: "square.grid.2x2",
        selection: .preferOne, order: 11)

    /// Game servers people invite friends to
    public static let games = ServiceCategory(
        id: "games", title: "Game servers",
        summary: "A Minecraft server on your own machine, with a web panel for the console, players and backups.",
        systemImage: "gamecontroller",
        selection: .multiple, order: 13)

    public static let ai = ServiceCategory(
        id: "ai", title: "AI",
        summary: "A model that runs on your own machine, and a chat in front of it: nothing you type, and none of the documents you feed it, leaves the server.",
        systemImage: "brain",
        selection: .multiple, order: -1)

    public static let automation = ServiceCategory(
        id: "automation", title: "Automation",
        summary: "Connects your services to each other: an event, then a step, then a step. Zapier, running on your own server.",
        systemImage: "arrow.triangle.branch",
        selection: .preferOne, order: 15)

    public static let smartHome = ServiceCategory(
        id: "smart-home", title: "Smart home",
        summary: "Runs the house from your own machine: lights, sensors, heating and cameras in one app, working even when the internet is down. Only on a machine at home.",
        systemImage: "house",
        selection: .multiple, order: 16)

    public static let implicit = ServiceCategory(
        id: "implicit", title: "", summary: "", systemImage: "gearshape",
        selection: .multiple, order: 99)

    /// Every category, in the order the forms show them
    public static let selectable: [ServiceCategory] = [
        .mail, .passwords, .secrets, .files, .photos, .media, .code, .network, .vpn, .mesh,
        .remoteAccess, .dashboard, .singleSignOn, .games, .ai, .automation, .smartHome
    ]
}
