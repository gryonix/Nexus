import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf

extension DemoAgentState {
    /// Host state, panel guard, devices, DNS, vault
    func control(_ path: String, _ request: Data,
                 _ machine: DemoAgentMachine) async throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Control/GetState":
            return await state(of: machine).demoPayload
        case "/gryonixnexusd.v1.Control/Discover":
            var found = Gryonixnexusd_V1_DiscoverResult()
            found.services = await state(of: machine).services
            return found.demoPayload
        case "/gryonixnexusd.v1.Control/MetricsHistory":
            let asked = try Gryonixnexusd_V1_MetricsHistoryRequest(serializedBytes: request)
            return history(bucket: asked.bucket, limit: asked.limit, machine: machine).demoPayload
        case "/gryonixnexusd.v1.Control/ListSerialDevices":
            return Self.serialDevices().demoPayload
        case "/gryonixnexusd.v1.Control/ServiceStatus":
            let asked = try Gryonixnexusd_V1_ServiceStatusRequest(serializedBytes: request)
            var answer = Gryonixnexusd_V1_ServiceStatusResponse()
            answer.service = await service(asked.serviceID, on: machine)
            return answer.demoPayload
        default:
            return try await lockdownOrPairing(path, request, machine)
        }
    }

    // MARK: - The host itself

    private func state(of machine: DemoAgentMachine) async -> Gryonixnexusd_V1_State {
        var state = Gryonixnexusd_V1_State()
        state.agentVersion = DemoAgentOffer.installedVersion
        state.host = Self.host(of: machine)
        state.discoveredAt = Int64(Date().timeIntervalSince1970 * 1000)
        var services: [Gryonixnexusd_V1_Service] = []
        for id in await present(machine) {
            services.append(await service(id.rawValue, on: machine))
        }
        state.services = services
        return state
    }

    private static func host(of machine: DemoAgentMachine) -> Gryonixnexusd_V1_Host {
        var host = Gryonixnexusd_V1_Host()
        host.hostname = machine.deployment.name
        host.osID = "debian"
        host.osPrettyName = "Debian GNU/Linux 13 (trixie)"
        host.arch = "aarch64"
        host.topology = machine.deployment.hasRelayIngress ? "relay" : "single"
        let domain = machine.deployment.domain
        host.servedHostnames = domain.isEmpty ? [] : ["\(domain)"]
        host.domains = domain.isEmpty ? [] : [domain]
        return host
    }

    private func service(_ id: String,
                         on machine: DemoAgentMachine) async -> Gryonixnexusd_V1_Service {
        var service = Gryonixnexusd_V1_Service()
        service.id = id
        service.displayName = ServiceRegistry.service(ServiceID(rawValue: id))?.displayName ?? id
        service.status = await isRunning(id, on: machine) ? .running : .stopped
        service.version = "1.0.0"
        var container = Gryonixnexusd_V1_Container()
        container.name = "\(id)-app-1"
        container.image = "\(id):latest"
        container.state = service.status == .running ? "running" : "exited"
        container.health = service.status == .running ? "healthy" : ""
        service.containers = [container]
        return service
    }

    private static func serialDevices() -> Gryonixnexusd_V1_SerialDeviceList {
        var device = Gryonixnexusd_V1_SerialDevice()
        device.path = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus-if00-port0"
        device.target = "/dev/ttyUSB0"
        device.label = "ITead Sonoff Zigbee 3.0 USB Dongle Plus"
        var list = Gryonixnexusd_V1_SerialDeviceList()
        list.devices = [device]
        list.directoryPresent = true
        return list
    }

    // MARK: - Panel guard, devices, DNS and the vault

    private func lockdownOrPairing(_ path: String, _ request: Data,
                                   _ machine: DemoAgentMachine) async throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Lockdown/GetLockdown":
            return await lockdown(machine).demoPayload
        case "/gryonixnexusd.v1.Lockdown/SetLockdown":
            let asked = try Gryonixnexusd_V1_SetLockdownRequest(serializedBytes: request)
            return try await setLockdown(asked, machine).demoPayload
        case "/gryonixnexusd.v1.Dns/GetDynamicDNS":
            return dynamicDNS(machine).demoPayload
        case "/gryonixnexusd.v1.Dns/SetDynamicDNS":
            return try setDynamicDNS(request, machine).demoPayload
        default:
            return try pairingOrVault(path, request, machine)
        }
    }

    private func lockdown(_ machine: DemoAgentMachine) async -> Gryonixnexusd_V1_LockdownState {
        let stored = await DemoFleetState.shared.lockdown(of: machine.id,
                                                          containers: machine.containers)
        var answer = Gryonixnexusd_V1_LockdownState()
        if stored == "on" {
            answer.mode = .all
        } else if stored.hasPrefix("only ") {
            answer.mode = .only
            answer.hosts = stored.dropFirst(5).split(separator: " ").map(String.init)
        } else {
            answer.mode = .off
        }
        return answer
    }

    private func setLockdown(_ asked: Gryonixnexusd_V1_SetLockdownRequest,
                             _ machine: DemoAgentMachine) async throws -> Gryonixnexusd_V1_LockdownState {
        let stored: String
        switch asked.mode {
        case .all: stored = "on"
        case .only: stored = asked.hosts.isEmpty ? "off" : "only \(asked.hosts.joined(separator: " "))"
        default: stored = "off"
        }
        await DemoFleetState.shared.setLockdown(stored, deployment: machine.id,
                                                containers: machine.containers)
        return await lockdown(machine)
    }

    private func dynamicDNS(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_DynamicDNSState {
        let stored = memory(machine)
        var answer = Gryonixnexusd_V1_DynamicDNSState()
        answer.enabled = stored.dynamicDNSEnabled
        answer.zone = machine.deployment.domain
        answer.names = stored.dynamicDNSNames
        answer.hasToken_p = stored.dynamicDNSEnabled
        answer.recent = stored.dynamicDNSEnabled
            ? ["\(Self.stamp()) updated \(machine.deployment.domain) -> 203.0.113.10"] : []
        return answer
    }

    private func setDynamicDNS(_ request: Data,
                               _ machine: DemoAgentMachine) throws -> Gryonixnexusd_V1_DynamicDNSState {
        let asked = try Gryonixnexusd_V1_SetDynamicDNSRequest(serializedBytes: request)
        var stored = memory(machine)
        stored.dynamicDNSEnabled = !asked.names.isEmpty
        stored.dynamicDNSNames = asked.names
        write(stored, for: machine)
        return dynamicDNS(machine)
    }

    private func pairingOrVault(_ path: String, _ request: Data,
                                _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Pairing/ListDevices":
            var list = Gryonixnexusd_V1_DeviceList()
            list.devices = memory(machine).devices
            return list.demoPayload
        case "/gryonixnexusd.v1.Pairing/Pair":
            var answer = Gryonixnexusd_V1_PairResponse()
            answer.device = try pair(request, machine)
            return answer.demoPayload
        case "/gryonixnexusd.v1.Pairing/Revoke":
            let asked = try Gryonixnexusd_V1_RevokeRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.devices.removeAll { $0.id == asked.deviceID }
            write(stored, for: machine)
            var answer = Gryonixnexusd_V1_RevokeResponse()
            answer.revoked = true
            return answer.demoPayload
        case "/gryonixnexusd.v1.Pairing/GetSessionPolicy":
            return sessionPolicy(machine).demoPayload
        case "/gryonixnexusd.v1.Pairing/SetSessionPolicy":
            let asked = try Gryonixnexusd_V1_SetSessionPolicyRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.autoLogoutMonths = asked.autoLogoutMonths
            write(stored, for: machine)
            return sessionPolicy(machine).demoPayload
        default:
            return try vault(path, request, machine)
        }
    }

    private func pair(_ request: Data,
                      _ machine: DemoAgentMachine) throws -> Gryonixnexusd_V1_Device {
        let asked = try Gryonixnexusd_V1_PairRequest(serializedBytes: request)
        var device = Gryonixnexusd_V1_Device()
        device.id = UUID().uuidString
        device.label = asked.label
        device.publicKey = asked.devicePublicKey
        device.deviceUid = asked.deviceUid
        device.scopes = ["read"]
        device.pairedAt = Int64(Date().timeIntervalSince1970 * 1000)
        var stored = memory(machine)
        stored.devices.append(device)
        write(stored, for: machine)
        return device
    }

    private func sessionPolicy(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_SessionPolicy {
        let stored = memory(machine)
        var answer = Gryonixnexusd_V1_SessionPolicy()
        answer.autoLogoutMonths = stored.autoLogoutMonths
        answer.deviceCount = Int32(stored.devices.count)
        return answer
    }

    static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }
}
