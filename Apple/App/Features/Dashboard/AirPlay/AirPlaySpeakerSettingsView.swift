import AgentClient
import ServerControl
import ServiceCatalog
import SwiftUI

/// Everything the AirPlay speaker can be set to
struct AirPlaySpeakerSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onUpdate: (Deployment) -> Void
    @State private var mode: String
    @State private var name: String
    @State private var output: String
    @State private var values: [String: String]
    @State private var outputs: [Gryonixnexusd_V1_AudioOutput] = []
    @State private var outputsError: String?
    @State private var applying = false
    @State private var applied = false

    init(viewModel: DashboardViewModel, onUpdate: @escaping (Deployment) -> Void) {
        self.viewModel = viewModel
        self.onUpdate = onUpdate
        let settings = viewModel.deployment.serviceSettings
        _mode = State(initialValue: settings.shairportMode)
        _name = State(initialValue: settings.shairportName)
        _output = State(initialValue: ShairportSyncService.playable(settings.shairportOutput))
        let pairs = ShairportSyncService.parsedOptions(settings.shairportOptions)
        _values = State(initialValue: Dictionary(pairs.map { ($0.key, $0.value) }) { _, last in last })
    }

    private var optionsText: String { ShairportSyncService.optionsText(values) }

    private var changed: Bool {
        let settings = viewModel.deployment.serviceSettings
        return mode != settings.shairportMode || name != settings.shairportName
            || output != ShairportSyncService.playable(settings.shairportOutput) || optionsText != settings.shairportOptions
    }

    var body: some View {
        Form {
            speakerSection
            outputSection
            if offersHDMIVolume { hdmiVolumeSection }
            settingsSection("Volume", note: "How the phone's volume slider maps to this speaker. Leave on Default unless the sound is too quiet or too loud.",
                            SpeakerSettingsCatalog.sound)
            settingsSection("Timing", note: "Sound delay moves the sound earlier (minus) or later (plus) to match a TV picture. A bigger buffer helps on a weak Wi‑Fi.",
                            SpeakerSettingsCatalog.timing)
            settingsSection("Output format", note: "Automatic suits almost every sound card. Keeping the output awake stops clicks some amplifiers make when they switch on.",
                            SpeakerSettingsCatalog.format)
            settingsSection("Sessions", note: "Whether another phone may interrupt what is playing, and when an idle phone lets go of the speaker.",
                            SpeakerSettingsCatalog.sessions)
        }
        .screenTitle("Speaker settings")
        .pendingChanges(phase, text: Self.pendingText, apply: apply, revert: revert)
        .task { await loadOutputs() }
        #if DEBUG
        .task { if DemoSpeakerScreen.asked == "edit" { name += " 2" } }
        .task { if DemoSpeakerScreen.asked == "hdmi" { values["cec_volume"] = "yes" } }
        #endif
    }

    private var speakerSection: some View {
        Section {
            WrappingPicker("AirPlay version", selection: $mode) {
                Text(verbatim: "AirPlay 2").tag("airplay2")
                Text(verbatim: "AirPlay 1").tag("airplay1")
            }
            .infoNote("AirPlay version", "AirPlay 2 joins HomePod and multi-room; AirPlay 1 works with every Apple device and allows track control. Switching restarts the speaker; music pauses for a few seconds.")
            TechnicalField(title: "Speaker name", prompt: "gryonix", text: $name, spokenName: true)
                .infoNote("Speaker name", "The name this speaker shows in the AirPlay list on your devices.")
        } header: {
            InfoSectionHeader("Speaker", note: "AirPlay 2 joins HomePod and multi-room; AirPlay 1 works with every Apple device and allows track control. Switching restarts the speaker; music pauses for a few seconds.")
        }
    }

    private var outputSection: some View {
        Section {
            AirPlayOutputPicker(outputs: outputs, error: outputsError, output: $output,
                                mixer: Binding(get: { values["mixer_control_name"] ?? "" },
                                               set: { values["mixer_control_name"] = $0 }))
        } header: {
            InfoSectionHeader("Output", note: "The sound card the music plays through, as this machine reports it. The volume control lets the phone move the card's own volume; without one, the volume is changed in software.")
        }
    }

    private var offersHDMIVolume: Bool {
        #if DEBUG
        if DemoSpeakerScreen.asked != nil { return true }
        #endif
        return output.contains("vc4hdmi")
    }

    private var hdmiVolumeSection: some View {
        let on = values["cec_volume"] == "yes"
        return settingsSection("HDMI volume",
                               note: "The phone's volume slider changes the volume of the TV or amplifier on the HDMI cable instead of the sound inside the speaker. The device must support HDMI-CEC.",
                               Array(SpeakerSettingsCatalog.hdmiVolume.prefix(on ? 8 : 1)))
    }

    private func settingsSection(_ title: LocalizedStringKey, note: LocalizedStringKey,
                                 _ settings: [SpeakerSetting]) -> some View {
        Section {
            ForEach(settings) { SpeakerSettingRow(setting: $0, values: $values) }
        } header: {
            InfoSectionHeader(title, note: note)
        }
    }

    private static let pendingText = PendingChangesText(
        apply: "Restart the speaker",
        note: "The speaker goes silent for a few seconds.",
        applying: "Restarting the speaker…")

    private var phase: PendingChangesPhase? {
        if applying { return .applying }
        if applied { return .done }
        return changed ? .waiting : nil
    }

    private func apply() {
        applying = true
        Task {
            let updated = await viewModel.setAirPlay(mode: mode, name: name, output: output, options: optionsText)
            if let updated { onUpdate(updated) }
            applied = updated != nil
            applying = false
            try? await Task.sleep(for: .seconds(1.5))
            applied = false
        }
    }

    /// Puts every field back to the stored settings
    private func revert() {
        let settings = viewModel.deployment.serviceSettings
        mode = settings.shairportMode
        name = settings.shairportName
        output = ShairportSyncService.playable(settings.shairportOutput)
        let pairs = ShairportSyncService.parsedOptions(settings.shairportOptions)
        values = Dictionary(pairs.map { ($0.key, $0.value) }) { _, last in last }
    }

    private func loadOutputs() async {
        do {
            outputs = try await viewModel.fetchAudioOutputs()
            outputsError = nil
        } catch {
            outputsError = error.localizedDescription
        }
    }
}
