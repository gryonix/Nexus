import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf

extension DemoAgentState {
    /// Intrusion defence and SSH access
    func security(_ path: String, _ request: Data,
                  _ machine: DemoAgentMachine) async throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Security/GetSecurityStatus":
            return Self.securityStatus(bans: memory(machine).bans).demoPayload
        case "/gryonixnexusd.v1.Security/GetSshPasswordState":
            return sshState(machine).demoPayload
        case "/gryonixnexusd.v1.Security/SetSshPasswordLogin":
            let asked = try Gryonixnexusd_V1_SetSshPasswordLoginRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.passwordLoginOpen = asked.allowPasswords
            write(stored, for: machine)
            return sshState(machine).demoPayload
        case "/gryonixnexusd.v1.Security/ListSshUsers":
            return sshUsers(machine).demoPayload
        case "/gryonixnexusd.v1.Security/SetSshKeyOnlyUsers":
            let asked = try Gryonixnexusd_V1_SetSshKeyOnlyUsersRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.keyOnlyUsers = asked.everyone ? Set(Self.accounts(machine)) : Set(asked.users)
            stored.passwordLoginOpen = !asked.everyone
            write(stored, for: machine)
            return sshUsers(machine).demoPayload
        default:
            return try decisions(path, request, machine)
        }
    }

    // MARK: - SSH accounts

    private static func accounts(_ machine: DemoAgentMachine) -> [String] {
        [machine.deployment.dashboardConfig.sshUser, "root", "backup"]
    }

    private func sshState(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_SshPasswordState {
        let stored = memory(machine)
        var answer = Gryonixnexusd_V1_SshPasswordState()
        answer.passwordLoginOpen = stored.passwordLoginOpen
        answer.known = true
        answer.appKeyPresent = true
        answer.dropInPresent = true
        answer.sshdPresent = true
        answer.loginUser = machine.deployment.dashboardConfig.sshUser
        return answer
    }

    private func sshUsers(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_SshUsers {
        let stored = memory(machine)
        let login = machine.deployment.dashboardConfig.sshUser
        var answer = Gryonixnexusd_V1_SshUsers()
        answer.known = true
        answer.host = sshState(machine)
        answer.users = Self.accounts(machine).map { name in
            var user = Gryonixnexusd_V1_SshUser()
            user.name = name
            user.known = true
            user.isLoginUser = name == login
            user.carriesKeys = !stored.lockedOutUsers.contains(name)
            user.appKeyPresent = name == login
            user.passwordLoginOpen = !stored.keyOnlyUsers.contains(name)
            return user
        }
        return answer
    }

    // MARK: - Blocked addresses

    private func decisions(_ path: String, _ request: Data,
                           _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Security/GetSecurityDecisions":
            return decisionList(machine).demoPayload
        case "/gryonixnexusd.v1.Security/SetSecurityDecision":
            let asked = try Gryonixnexusd_V1_SetSecurityDecisionRequest(serializedBytes: request)
            var stored = memory(machine)
            if asked.banned {
                stored.bans.insert(Self.handMade(asked), at: 0)
            } else {
                stored.bans.removeAll { $0.value == asked.value || $0.id == asked.id }
            }
            write(stored, for: machine)
            return decisionList(machine).demoPayload
        case "/gryonixnexusd.v1.Security/GetSecurityAllowlist":
            return allowlist(machine).demoPayload
        case "/gryonixnexusd.v1.Security/SetSecurityAllowlist":
            let asked = try Gryonixnexusd_V1_SetSecurityAllowlistRequest(serializedBytes: request)
            var stored = memory(machine)
            if asked.allowed {
                stored.allowlist.removeAll { $0.value == asked.value }
                stored.allowlist.append(Allowed(value: asked.value, comment: asked.comment))
                stored.bans.removeAll { $0.value == asked.value }
            } else {
                stored.allowlist.removeAll { $0.value == asked.value }
            }
            write(stored, for: machine)
            return allowlist(machine).demoPayload
        default:
            return try autoRules(path, request, machine)
        }
    }

    private func decisionList(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_SecurityDecisions {
        var answer = Gryonixnexusd_V1_SecurityDecisions()
        answer.present = true
        answer.communityCount = 17_707
        answer.sshClientIps = Self.sshClientIPs
        answer.decisions = memory(machine).bans.map { ban in
            var decision = Gryonixnexusd_V1_SecurityDecision()
            decision.id = ban.id
            decision.scope = ban.scope
            decision.value = ban.value
            decision.action = "ban"
            decision.reason = ban.reason
            decision.country = ban.country
            decision.asName = ban.asName
            decision.source = ban.source
            decision.expiresIn = ban.expiresIn
            decision.events = ban.events
            return decision
        }
        return answer
    }

    static let sshClientIPs = ["198.51.100.9"]

    /// A ban somebody made from the app
    private static func handMade(_ asked: Gryonixnexusd_V1_SetSecurityDecisionRequest) -> Ban {
        Ban(id: "\(Int.random(in: 300_000..<400_000))",
            scope: asked.value.contains("/") ? "Range" : "Ip",
            value: asked.value,
            reason: asked.reason.isEmpty ? "gryonixnexus: added by hand" : asked.reason,
            country: "", asName: "", source: "cscli",
            expiresIn: Self.readable(asked.durationSeconds), events: 1)
    }

    private static func readable(_ seconds: UInt64) -> String {
        guard seconds > 0 else { return "" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)m"
    }

    private func allowlist(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_SecurityAllowlist {
        var answer = Gryonixnexusd_V1_SecurityAllowlist()
        answer.present = true
        answer.supported = true
        answer.name = "gryonixnexus"
        answer.sshClientIps = Self.sshClientIPs
        answer.entries = memory(machine).allowlist.map { allowed in
            var entry = Gryonixnexusd_V1_SecurityAllowlistEntry()
            entry.value = allowed.value
            entry.comment = allowed.comment
            return entry
        }
        return answer
    }

    private func autoRules(_ path: String, _ request: Data,
                           _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Security/GetSecurityAutoRules":
            return rules(machine).demoPayload
        case "/gryonixnexusd.v1.Security/SetSecurityAutoRules":
            let asked = try Gryonixnexusd_V1_SetSecurityAutoRulesRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.autoRulesEnabled = asked.rules.enabled
            stored.autoRuleCountries = asked.rules.countries
            write(stored, for: machine)
            return rules(machine).demoPayload
        default:
            return nil
        }
    }

    private func rules(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_SecurityAutoRules {
        let stored = memory(machine)
        var answer = Gryonixnexusd_V1_SecurityAutoRules()
        answer.enabled = stored.autoRulesEnabled
        answer.countries = stored.autoRuleCountries
        answer.attemptThreshold = 5
        answer.attemptWindowMinutes = 10
        answer.banSubnet = false
        answer.banSeconds = 14_400
        answer.geoipAvailable = true
        return answer
    }

    // MARK: - What the defence reports

    static func securityStatus(bans: [Ban]) -> Gryonixnexusd_V1_SecurityStatus {
        var answer = Gryonixnexusd_V1_SecurityStatus()
        answer.present = true
        answer.engineRunning = true
        answer.bouncerRunning = true
        answer.engineVersion = "v1.8.1"
        answer.alerts24H = 49
        answer.localBans = UInt32(bans.count)
        answer.communityBlocklistIps = 17_707
        answer.packetsDropped = 17_800
        var scenario = Gryonixnexusd_V1_SecurityScenario()
        scenario.name = "crowdsecurity/ssh-bf"
        scenario.count = 37
        answer.topScenarios = [scenario]
        answer.recentBans = bans.prefix(3).map { held in
            var ban = Gryonixnexusd_V1_SecurityBan()
            ban.ip = held.value
            ban.country = held.country.isEmpty ? "RU" : held.country
            ban.scenario = held.reason
            ban.at = "2026-09-12T15:52:20Z"
            return ban
        }
        return answer
    }
}
