import Foundation

public struct HostSecurityStatus: Sendable, Hashable {
    /// The host answered; false means the read itself failed
    public let isKnown: Bool
    public let isPresent: Bool
    public let engineRunning: Bool
    public let bouncerRunning: Bool
    /// e.g
    public let engineVersion: String
    public let alertsLast24h: Int
    public let localBans: Int
    public let communityBlocklistIPs: Int
    /// Packets the bouncer has dropped since it started
    public let packetsDropped: Int
    public let topScenarios: [Scenario]
    /// The most recent attacks, newest first
    public let recentBans: [Ban]

    public struct Scenario: Sendable, Hashable, Identifiable {
        /// The CrowdSec scenario id, e.g
        public let name: String
        public let count: Int
        public var id: String { name }

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }

        public var readableName: String {
            let tail = name.split(separator: "/").last.map(String.init) ?? name
            switch tail {
            case "ssh-bf", "ssh-bf_user-enum": return "SSH brute force"
            case "ssh-slow-bf", "ssh-slow-bf_user-enum": return "SSH slow brute force"
            case "ssh-time-based-bf", "ssh-time-based-bf_user-enum": return "SSH timed brute force"
            case "ssh-cve-2024-6387": return "SSH regreSSHion probe (CVE-2024-6387)"
            case "http-bf", "http-generic-bf": return "Web login brute force"
            case "http-crawl-non_statics": return "Aggressive web crawling"
            case "http-probing": return "Web path probing"
            case "http-sensitive-files": return "Sensitive-file scanning"
            default:
                return tail.replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
            }
        }
    }

    public struct Ban: Sendable, Hashable, Identifiable {
        public let ip: String
        /// Two-letter country code, or "" when CrowdSec could not place it
        public let country: String
        public let scenario: String
        /// CrowdSec's own RFC 3339 timestamp string, or "" if absent
        public let at: String
        public var id: String { "\(ip)|\(scenario)|\(at)" }

        public init(ip: String, country: String, scenario: String, at: String) {
            self.ip = ip
            self.country = country
            self.scenario = scenario
            self.at = at
        }

        public var date: Date? {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: at) { return d }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.date(from: at)
        }
    }

    public init(isPresent: Bool, engineRunning: Bool, bouncerRunning: Bool,
                engineVersion: String, alertsLast24h: Int, localBans: Int,
                communityBlocklistIPs: Int, packetsDropped: Int,
                topScenarios: [Scenario], recentBans: [Ban], isKnown: Bool = true) {
        self.isKnown = isKnown
        self.isPresent = isPresent
        self.engineRunning = engineRunning
        self.bouncerRunning = bouncerRunning
        self.engineVersion = engineVersion
        self.alertsLast24h = alertsLast24h
        self.localBans = localBans
        self.communityBlocklistIPs = communityBlocklistIPs
        self.packetsDropped = packetsDropped
        self.topScenarios = topScenarios
        self.recentBans = recentBans
    }

    /// Protection is in place and both halves are up
    public var isHealthy: Bool { isPresent && engineRunning && bouncerRunning }

    /// The read failed
    public static let unknown = HostSecurityStatus(
        isPresent: false, engineRunning: false, bouncerRunning: false,
        engineVersion: "", alertsLast24h: 0, localBans: 0,
        communityBlocklistIPs: 0, packetsDropped: 0,
        topScenarios: [], recentBans: [], isKnown: false)
}

public struct SSHPasswordAccess: Sendable, Hashable {
    /// sshd accepts passwords right now
    public let passwordLoginOpen: Bool
    public let isKnown: Bool
    public let appKeyPresent: Bool
    /// This product's drop-in is on disk
    public let dropInPresent: Bool
    public let sshdPresent: Bool
    public let loginUser: String
    public let detail: String

    public init(passwordLoginOpen: Bool, isKnown: Bool, appKeyPresent: Bool,
                dropInPresent: Bool, sshdPresent: Bool, loginUser: String, detail: String) {
        self.passwordLoginOpen = passwordLoginOpen
        self.isKnown = isKnown
        self.appKeyPresent = appKeyPresent
        self.dropInPresent = dropInPresent
        self.sshdPresent = sshdPresent
        self.loginUser = loginUser
        self.detail = detail
    }

    /// The host said what it accepts and it accepts passwords
    public var isOpen: Bool { isKnown && passwordLoginOpen }
    /// The host said what it accepts and it refuses them
    public var isClosed: Bool { isKnown && !passwordLoginOpen }

    public var canClose: Bool { isOpen && appKeyPresent }

    public var isOutranked: Bool { isKnown && passwordLoginOpen && dropInPresent }

    public static let unknown = SSHPasswordAccess(
        passwordLoginOpen: false, isKnown: false, appKeyPresent: false,
        dropInPresent: false, sshdPresent: false, loginUser: "", detail: "")
}

/// One account on the host and what its SSH accepts
public struct SSHUserAccess: Sendable, Hashable, Identifiable {
    public let name: String
    public let passwordLoginOpen: Bool
    /// sshd answered about THIS account
    public let isKnown: Bool
    /// The account carries a key of its own
    public let hasKeys: Bool
    public let appKeyPresent: Bool
    /// The account the app signs in with
    public let isLoginUser: Bool

    public var id: String { name }

    public init(name: String, passwordLoginOpen: Bool, isKnown: Bool, hasKeys: Bool,
                appKeyPresent: Bool, isLoginUser: Bool) {
        self.name = name
        self.passwordLoginOpen = passwordLoginOpen
        self.isKnown = isKnown
        self.hasKeys = hasKeys
        self.appKeyPresent = appKeyPresent
        self.isLoginUser = isLoginUser
    }

    /// The host refuses passwords for this account
    public var isClosed: Bool { isKnown && !passwordLoginOpen }

    /// Closing this one would leave nobody a way in
    public var wouldLockOut: Bool { !hasKeys }
}

/// The accounts of one host
public struct SSHUsers: Sendable, Hashable {
    public let users: [SSHUserAccess]
    public let host: SSHPasswordAccess
    /// What the last change did, in the host's own words
    public let detail: String
    /// The host answered at all
    public let isKnown: Bool

    public init(users: [SSHUserAccess], host: SSHPasswordAccess, detail: String, isKnown: Bool) {
        self.users = users
        self.host = host
        self.detail = detail
        self.isKnown = isKnown
    }

    public static let unknown = SSHUsers(users: [], host: .unknown, detail: "", isKnown: false)

    /// Every account refuses passwords
    public var isClosedForEveryone: Bool {
        !users.isEmpty && users.allSatisfy(\.isClosed)
    }

    /// The accounts that refuse passwords right now
    public var closedNames: [String] { users.filter(\.isClosed).map(\.name) }

    /// The host reading, closed when every account is closed
    public var hostAccess: SSHPasswordAccess {
        guard host.isKnown, host.passwordLoginOpen, isClosedForEveryone else { return host }
        return SSHPasswordAccess(passwordLoginOpen: false, isKnown: true,
                                 appKeyPresent: host.appKeyPresent,
                                 dropInPresent: host.dropInPresent,
                                 sshdPresent: host.sshdPresent,
                                 loginUser: host.loginUser, detail: host.detail)
    }
}

public struct HostSecurityDecisions: Sendable, Hashable {
    public let isPresent: Bool
    public let decisions: [Decision]
    /// How many addresses the COMMUNITY blocklist is blocking
    public let communityCount: Int
    public let sshClientIPs: [String]

    public struct Decision: Sendable, Hashable, Identifiable {
        /// CrowdSec's own decision id
        public let decisionID: String
        /// "Ip", "Range", "Country" — CrowdSec's own word
        public let scope: String
        public let value: String
        public let action: String
        public let reason: String
        public let country: String
        public let asName: String
        public let source: String
        public let expiresIn: String
        public let events: Int

        public var id: String { decisionID.isEmpty ? "\(source)|\(value)" : decisionID }

        public var isManual: Bool { source == "cscli" }

        public init(decisionID: String, scope: String, value: String, action: String,
                    reason: String, country: String, asName: String, source: String,
                    expiresIn: String, events: Int) {
            self.decisionID = decisionID
            self.scope = scope
            self.value = value
            self.action = action
            self.reason = reason
            self.country = country
            self.asName = asName
            self.source = source
            self.expiresIn = expiresIn
            self.events = events
        }

        public var readableReason: String {
            guard reason.contains("/") else { return reason }
            return HostSecurityStatus.Scenario(name: reason, count: 0).readableName
        }
    }

    public init(isPresent: Bool, decisions: [Decision], communityCount: Int,
                sshClientIPs: [String]) {
        self.isPresent = isPresent
        self.decisions = decisions
        self.communityCount = communityCount
        self.sshClientIPs = sshClientIPs
    }

    public static let unknown = HostSecurityDecisions(
        isPresent: false, decisions: [], communityCount: 0, sshClientIPs: [])
}

/// The addresses this host will never ban
public struct HostSecurityAllowlist: Sendable, Hashable {
    public let isPresent: Bool
    public let isSupported: Bool
    public let name: String
    public let entries: [Entry]
    public let sshClientIPs: [String]

    public struct Entry: Sendable, Hashable, Identifiable {
        public let value: String
        public let comment: String
        /// As CrowdSec prints it; empty when the entry never expires
        public let expiresIn: String
        public var id: String { value }

        public init(value: String, comment: String, expiresIn: String) {
            self.value = value
            self.comment = comment
            self.expiresIn = expiresIn
        }
    }

    public init(isPresent: Bool, isSupported: Bool, name: String,
                entries: [Entry], sshClientIPs: [String]) {
        self.isPresent = isPresent
        self.isSupported = isSupported
        self.name = name
        self.entries = entries
        self.sshClientIPs = sshClientIPs
    }

    public func allows(_ value: String) -> Bool {
        entries.contains { $0.value == value }
    }

    public static let unknown = HostSecurityAllowlist(
        isPresent: false, isSupported: false, name: "", entries: [], sshClientIPs: [])
}

public struct HostSecurityAutoRules: Sendable, Hashable, Codable {
    public var isOn: Bool
    /// ISO 3166-1 alpha-2 codes, as CrowdSec enriches them
    public var countries: [String]
    public var countriesAreAllowlist: Bool
    /// N failures is an attack
    public var attemptThreshold: Int
    /// The window those failures are counted in
    public var attemptWindowMinutes: Int
    /// Ban the neighbourhood rather than the address — `/24` for IPv4
    public var bansSubnet: Bool
    /// How long a ban from these rules lasts
    public var banSeconds: TimeInterval
    /// Per-service sharpening: SSH answered harder than a web form
    public var services: [ServiceRule]
    public var geoIPAvailable: Bool

    public struct ServiceRule: Sendable, Hashable, Codable, Identifiable {
        /// The scenario family this sharpens — "ssh", "http", "smtp"
        public var service: String
        public var attemptThreshold: Int
        public var banSeconds: TimeInterval

        public var id: String { service }

        public init(service: String, attemptThreshold: Int = 0, banSeconds: TimeInterval = 0) {
            self.service = service
            self.attemptThreshold = attemptThreshold
            self.banSeconds = banSeconds
        }
    }

    public init(isOn: Bool = false, countries: [String] = [],
                countriesAreAllowlist: Bool = false, attemptThreshold: Int = 0,
                attemptWindowMinutes: Int = 0, bansSubnet: Bool = false,
                banSeconds: TimeInterval = 0, services: [ServiceRule] = [],
                geoIPAvailable: Bool = false) {
        self.isOn = isOn
        self.countries = countries
        self.countriesAreAllowlist = countriesAreAllowlist
        self.attemptThreshold = attemptThreshold
        self.attemptWindowMinutes = attemptWindowMinutes
        self.bansSubnet = bansSubnet
        self.banSeconds = banSeconds
        self.services = services
        self.geoIPAvailable = geoIPAvailable
    }

    /// Whether these orders say anything at all
    public var isEmpty: Bool {
        countries.isEmpty && attemptThreshold == 0 && services.isEmpty
    }
}
