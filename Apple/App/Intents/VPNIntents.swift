import AppIntents
import Foundation

struct SetVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn VPN on or off"
    static var description = IntentDescription("Turns this device's tunnel on or off.")
    static var openAppWhenRun = false

    @Parameter(title: "On", default: true)
    var isOn: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Turn VPN \(\.$isOn)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if isOn { await TunnelController.shared.connect() } else { await TunnelController.shared.disconnect() }
        return .result()
    }
}

struct ToggleVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle VPN"
    static var description = IntentDescription("Switches this device's tunnel to the opposite state.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await TunnelController.shared.toggle()
        return .result()
    }
}
