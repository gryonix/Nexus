import AgentClient
import Foundation
import ServerControl

public struct AgentSecurityOperations {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func status() async throws -> HostSecurityStatus {
        let proto: Gryonixnexusd_V1_SecurityStatus
        if let gate {
            proto = try await gate.withSlot { try await client.getSecurityStatus() }
        } else {
            proto = try await client.getSecurityStatus()
        }
        return Self.status(from: proto)
    }

    public func sshPasswordAccess(loginUser: String,
                                  appPublicKey: String) async throws -> SSHPasswordAccess {
        let proto: Gryonixnexusd_V1_SshPasswordState
        if let gate {
            proto = try await gate.withSlot {
                try await client.getSSHPasswordState(loginUser: loginUser, appPublicKey: appPublicKey)
            }
        } else {
            proto = try await client.getSSHPasswordState(loginUser: loginUser, appPublicKey: appPublicKey)
        }
        return Self.access(from: proto)
    }

    /// Close SSH password login, or allow it again
    @discardableResult
    public func setSSHPasswordLogin(open: Bool, loginUser: String,
                                    appPublicKey: String) async throws -> SSHPasswordAccess {
        let proto: Gryonixnexusd_V1_SshPasswordState
        if let gate {
            proto = try await gate.withSlot {
                try await client.setSSHPasswordLogin(open: open, loginUser: loginUser,
                                                     appPublicKey: appPublicKey)
            }
        } else {
            proto = try await client.setSSHPasswordLogin(open: open, loginUser: loginUser,
                                                         appPublicKey: appPublicKey)
        }
        return Self.access(from: proto)
    }

    /// Every account and what its SSH accepts
    public func sshUsers(loginUser: String, appPublicKey: String) async throws -> SSHUsers {
        let proto: Gryonixnexusd_V1_SshUsers
        if let gate {
            proto = try await gate.withSlot {
                try await client.listSSHUsers(loginUser: loginUser, appPublicKey: appPublicKey)
            }
        } else {
            proto = try await client.listSSHUsers(loginUser: loginUser, appPublicKey: appPublicKey)
        }
        return Self.users(from: proto)
    }

    /// Key login only: everyone, some accounts, or none
    @discardableResult
    public func setKeyOnlyUsers(everyone: Bool, users: [String], loginUser: String,
                                appPublicKey: String) async throws -> SSHUsers {
        let proto: Gryonixnexusd_V1_SshUsers
        if let gate {
            proto = try await gate.withSlot {
                try await client.setSSHKeyOnlyUsers(everyone: everyone, users: users,
                                                    loginUser: loginUser,
                                                    appPublicKey: appPublicKey)
            }
        } else {
            proto = try await client.setSSHKeyOnlyUsers(everyone: everyone, users: users,
                                                        loginUser: loginUser,
                                                        appPublicKey: appPublicKey)
        }
        return Self.users(from: proto)
    }

    static func users(from proto: Gryonixnexusd_V1_SshUsers) -> SSHUsers {
        SSHUsers(
            users: proto.users.map {
                SSHUserAccess(name: $0.name, passwordLoginOpen: $0.passwordLoginOpen,
                              isKnown: $0.known, hasKeys: $0.carriesKeys,
                              appKeyPresent: $0.appKeyPresent, isLoginUser: $0.isLoginUser)
            },
            host: proto.hasHost ? access(from: proto.host) : .unknown,
            detail: proto.detail,
            isKnown: proto.known)
    }

    static func access(from proto: Gryonixnexusd_V1_SshPasswordState) -> SSHPasswordAccess {
        SSHPasswordAccess(
            passwordLoginOpen: proto.passwordLoginOpen,
            isKnown: proto.known,
            appKeyPresent: proto.appKeyPresent,
            dropInPresent: proto.dropInPresent,
            sshdPresent: proto.sshdPresent,
            loginUser: proto.loginUser,
            detail: proto.detail)
    }

    public enum Action: String, Sendable, CaseIterable {
        case start, stop, restart, update, install, remove

        var proto: Gryonixnexusd_V1_SecurityAction {
            switch self {
            case .start: return .start
            case .stop: return .stop
            case .restart: return .restart
            case .update: return .update
            case .install: return .install
            case .remove: return .remove
            }
        }

        public var isDestructive: Bool { self == .remove || self == .stop }
    }

    /// One progress line of a running operation, or its result
    public enum Progress: Sendable {
        /// A line the command printed, exactly as it printed it
        case line(String)
        case finished(HostSecurityStatus)
    }

    public func control(_ action: Action) -> AsyncThrowingStream<Progress, Error> {
        let client = self.client
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in client.controlSecurity(action: action.proto) {
                        switch event.phase {
                        case .progress:
                            let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty { continuation.yield(.line(text)) }
                        case .completed:
                            continuation.yield(.finished(Self.status(from: event.status)))
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Bans and the allowlist

    /// Who the host is blocking right now
    public func decisions() async throws -> HostSecurityDecisions {
        let proto = try await withSlot { try await client.getSecurityDecisions() }
        return Self.decisions(from: proto)
    }

    /// Ban an address by hand, or lift a ban
    @discardableResult
    public func setBan(_ banned: Bool, value: String, decisionID: String = "",
                       duration: TimeInterval = 0,
                       reason: String = "") async throws -> HostSecurityDecisions {
        let proto = try await withSlot {
            try await client.setSecurityDecision(value: value, banned: banned, id: decisionID,
                                                 duration: duration, reason: reason)
        }
        return Self.decisions(from: proto)
    }

    /// The addresses this host will never ban
    public func allowlist() async throws -> HostSecurityAllowlist {
        let proto = try await withSlot { try await client.getSecurityAllowlist() }
        return Self.allowlist(from: proto)
    }

    /// Put an address beyond banning, or stop protecting it
    @discardableResult
    public func setAllowed(_ allowed: Bool, value: String, comment: String = "",
                           duration: TimeInterval = 0) async throws -> HostSecurityAllowlist {
        let proto = try await withSlot {
            try await client.setSecurityAllowlist(value: value, allowed: allowed,
                                                  comment: comment, duration: duration)
        }
        return Self.allowlist(from: proto)
    }

    /// The standing orders behind every decision above
    public func autoRules() async throws -> HostSecurityAutoRules {
        Self.autoRules(from: try await withSlot { try await client.getSecurityAutoRules() })
    }

    @discardableResult
    public func setAutoRules(_ rules: HostSecurityAutoRules) async throws -> HostSecurityAutoRules {
        let proto: Gryonixnexusd_V1_SecurityAutoRules = {
            var wire = Gryonixnexusd_V1_SecurityAutoRules()
            wire.enabled = rules.isOn
            wire.countries = rules.countries
            wire.countriesAreAllowlist = rules.countriesAreAllowlist
            wire.attemptThreshold = UInt32(max(rules.attemptThreshold, 0))
            wire.attemptWindowMinutes = UInt32(max(rules.attemptWindowMinutes, 0))
            wire.banSubnet = rules.bansSubnet
            wire.banSeconds = UInt64(max(rules.banSeconds, 0))
            wire.services = rules.services.map { rule in
                var service = Gryonixnexusd_V1_SecurityServiceRule()
                service.service = rule.service
                service.attemptThreshold = UInt32(max(rule.attemptThreshold, 0))
                service.banSeconds = UInt64(max(rule.banSeconds, 0))
                return service
            }
            return wire
        }()
        return Self.autoRules(from: try await withSlot {
            try await client.setSecurityAutoRules(proto)
        })
    }

    static func autoRules(from proto: Gryonixnexusd_V1_SecurityAutoRules) -> HostSecurityAutoRules {
        HostSecurityAutoRules(
            isOn: proto.enabled,
            countries: proto.countries,
            countriesAreAllowlist: proto.countriesAreAllowlist,
            attemptThreshold: Int(proto.attemptThreshold),
            attemptWindowMinutes: Int(proto.attemptWindowMinutes),
            bansSubnet: proto.banSubnet,
            banSeconds: TimeInterval(proto.banSeconds),
            services: proto.services.map {
                HostSecurityAutoRules.ServiceRule(service: $0.service,
                                                  attemptThreshold: Int($0.attemptThreshold),
                                                  banSeconds: TimeInterval($0.banSeconds))
            },
            geoIPAvailable: proto.geoipAvailable)
    }

    private func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        guard let gate else { return try await body() }
        return try await gate.withSlot(body)
    }

    static func decisions(from proto: Gryonixnexusd_V1_SecurityDecisions) -> HostSecurityDecisions {
        HostSecurityDecisions(
            isPresent: proto.present,
            decisions: proto.decisions.map {
                HostSecurityDecisions.Decision(
                    decisionID: $0.id, scope: $0.scope, value: $0.value, action: $0.action,
                    reason: $0.reason, country: $0.country, asName: $0.asName,
                    source: $0.source, expiresIn: $0.expiresIn, events: Int($0.events))
            },
            communityCount: Int(proto.communityCount),
            sshClientIPs: proto.sshClientIps)
    }

    static func allowlist(from proto: Gryonixnexusd_V1_SecurityAllowlist) -> HostSecurityAllowlist {
        HostSecurityAllowlist(
            isPresent: proto.present,
            isSupported: proto.supported,
            name: proto.name,
            entries: proto.entries.map {
                HostSecurityAllowlist.Entry(value: $0.value, comment: $0.comment,
                                            expiresIn: $0.expiresIn)
            },
            sshClientIPs: proto.sshClientIps)
    }

    static func status(from proto: Gryonixnexusd_V1_SecurityStatus) -> HostSecurityStatus {
        HostSecurityStatus(
            isPresent: proto.present,
            engineRunning: proto.engineRunning,
            bouncerRunning: proto.bouncerRunning,
            engineVersion: proto.engineVersion,
            alertsLast24h: Int(proto.alerts24H),
            localBans: Int(proto.localBans),
            communityBlocklistIPs: Int(proto.communityBlocklistIps),
            packetsDropped: Int(proto.packetsDropped),
            topScenarios: proto.topScenarios.map {
                HostSecurityStatus.Scenario(name: $0.name, count: Int($0.count))
            },
            recentBans: proto.recentBans.map {
                HostSecurityStatus.Ban(ip: $0.ip, country: $0.country,
                                       scenario: $0.scenario, at: $0.at)
            })
    }
}
