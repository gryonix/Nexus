import AgentClient
import AgentControl
import ServerControl
import ServiceCatalog

extension DashboardViewModel {
    /// Re-applies the AirPlay speaker with other settings
    func setAirPlay(mode: String, name: String, output: String, options: String) async -> Deployment? {
        var changed = deployment
        changed.serviceSettings.shairportMode = mode
        changed.serviceSettings.shairportName = name
        changed.serviceSettings.shairportOutput = output
        changed.serviceSettings.shairportOptions = options
        replaceDeployment(changed)
        return await installService(ShairportSyncService())
    }

    /// The machine's sound outputs, as the agent reads them
    func fetchAudioOutputs() async throws -> [Gryonixnexusd_V1_AudioOutput] {
        guard #available(macOS 15.0, *) else {
            throw ServerControlError.notConfigured(UIL10n.string("This needs a newer system."))
        }
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        let gate = agentGate
        return try await gate.withSlot { try await client.listAudioOutputs() }
    }
}

extension DashboardViewModel {
    /// Re-applies a packaged speaker under another name
    func setSpeakerName(_ name: String, reinstalling service: any ManagedService) async -> Deployment? {
        var changed = deployment
        changed.serviceSettings.speakerName = PackagedAudioService.speakerName(name)
        replaceDeployment(changed)
        return await installService(service)
    }

    /// Re-applies the AirPlay screen under another name
    func setAirPlayScreen(name: String) async -> Deployment? {
        var changed = deployment
        changed.serviceSettings.uxplayName = name
        replaceDeployment(changed)
        return await installService(UxPlayService())
    }
}
