import ServerControl
import SwiftUI

/// Remote control for the odio audio hub
struct AudioHubView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var state: AudioHubState?
    @State private var error: String?
    @State private var volume: Double = 0
    @State private var draft = AudioHubDraft()
    @State private var sources = AudioHubSources()
    @State private var sourcesDraft = AudioHubSources()
    @StateObject private var edits = PendingRowEdits()

    var body: some View {
        Form {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let state, !showsOnlySources {
                AudioHubVolumeSection(state: state, volume: $volume, draft: $draft, run: run)
                AudioHubPlayersSection(players: state.players, run: run)
                AudioHubServicesSection(services: state.services, draft: $draft)
                AudioHubBluetoothSection(state: state, draft: $draft, run: run)
                AudioHubSourcesSections(saved: sources, draft: $sourcesDraft)
            } else if showsOnlySources {
                AudioHubSourcesSections(saved: sources, draft: $sourcesDraft)
            } else if error == nil {
                ProgressView()
            }
        }
        .screenTitle("Audio hub")
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: draft) { offerEdit() }
        .onChange(of: sourcesDraft) { offerSourcesEdit() }
        .pendingRowEdits(edits)
    }

    private var showsOnlySources: Bool {
        #if DEBUG
        return DemoSpeakerScreen.asked == "hub"
        #else
        return false
        #endif
    }

    /// Tells the bar whether hub settings wait
    private func offerEdit() {
        let field = $draft
        let edit = PendingRowEdits.Edit(
            id: "audio-hub", text: .apply,
            apply: { await applyDraft(field.wrappedValue) },
            revert: { field.wrappedValue = AudioHubDraft() })
        edits.offer(edit, changed: state.map { !draft.calls(against: $0).isEmpty } ?? false)
    }

    /// Tells the bar whether player settings wait
    private func offerSourcesEdit() {
        let edit = PendingRowEdits.Edit(
            id: "audio-hub-sources", text: .apply,
            apply: { await applySources() },
            revert: { sourcesDraft = sources })
        edits.offer(edit, changed: sourcesDraft.changes(from: sources) != nil)
    }

    /// Sends the edited player settings; the hub answers with all
    private func applySources() async -> Bool {
        guard let changes = sourcesDraft.changes(from: sources) else { return true }
        do {
            take(AudioHubSources(json: try await viewModel.odio("POST", AudioHubSources.path, body: changes)))
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func take(_ fresh: AudioHubSources) {
        sources = fresh
        sourcesDraft = fresh
    }

    /// Sends every waiting setting, then reads the hub
    private func applyDraft(_ asked: AudioHubDraft) async -> Bool {
        guard let state else { return false }
        do {
            for call in asked.calls(against: state) {
                try await viewModel.odio("POST", call, body: "")
            }
            draft = AudioHubDraft()
            await reload()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func reload() async {
        #if DEBUG
        if showsOnlySources, DemoDeployments.fromEnvironment() != nil { return take(AudioHubSources.demo) }
        #endif
        do {
            let fresh = try await viewModel.fetchAudioHub()
            state = fresh
            volume = fresh.volume
            error = nil
            if sourcesDraft == sources, let read = try? await viewModel.odio("GET", AudioHubSources.path) {
                take(AudioHubSources(json: read))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ path: String, _ body: String) {
        Task {
            do {
                try await viewModel.odio("POST", path, body: body)
                await reload()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Master volume, mute and the output
struct AudioHubVolumeSection: View {
    let state: AudioHubState
    @Binding var volume: Double
    @Binding var draft: AudioHubDraft
    let run: (String, String) -> Void

    var body: some View {
        Section {
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1) { editing in
                    if !editing { run("/audio/server/volume", AudioHubParser.volumeBody(volume)) }
                }
                Text(verbatim: "\(AudioHubState.percent(volume))%").monospacedDigit().foregroundStyle(.secondary)
            }
            Toggle("Mute", isOn: Binding(get: { state.muted }, set: { _ in run("/audio/server/mute", "") }))
            if state.outputs.count > 1 {
                Picker("Output", selection: Binding(
                    get: { draft.output ?? state.defaultOutput },
                    set: { draft.output = $0 })) {
                    ForEach(state.outputs) { Text(verbatim: $0.title).tag($0.name) }
                }
            }
        } header: {
            InfoSectionHeader("Volume", note: "The volume of the whole machine. Players have their own volume on top of it; the output is the sound card or speaker the music goes to.")
        }
    }
}

/// What each player is playing, with track buttons
struct AudioHubPlayersSection: View {
    let players: [AudioHubState.Player]
    let run: (String, String) -> Void

    var body: some View {
        Section("Now playing") {
            if players.isEmpty {
                Text("Nothing is playing").foregroundStyle(.secondary)
            }
            ForEach(players) { player in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: player.identity).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: player.title.isEmpty ? "—" : player.title).font(.headline)
                    if !player.artist.isEmpty { Text(verbatim: player.artist).foregroundStyle(.secondary) }
                    AudioHubTransport(player: player, run: run)
                }
            }
        }
    }
}

/// Track buttons for one player
struct AudioHubTransport: View {
    let player: AudioHubState.Player
    let run: (String, String) -> Void

    var body: some View {
        HStack(spacing: 28) {
            button("backward.fill", "Previous", "previous").disabled(!player.canGoPrevious)
            button(player.isPlaying ? "pause.fill" : "play.fill", player.isPlaying ? "Pause" : "Play", "play_pause")
            button("forward.fill", "Next", "next").disabled(!player.canGoNext)
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
    }

    private func button(_ image: String, _ label: LocalizedStringKey, _ verb: String) -> some View {
        Button { run("/players/\(player.busName)/\(verb)", "") } label: {
            Label(label, systemImage: image).labelStyle(.iconOnly).font(.title3)
        }
    }
}

/// Players the hub runs, each on or off
struct AudioHubServicesSection: View {
    let services: [AudioHubState.Service]
    @Binding var draft: AudioHubDraft

    var body: some View {
        if !services.isEmpty {
            Section {
                ForEach(services) { service in
                    Toggle(isOn: Binding(get: { draft.players[service.unit] ?? service.running },
                                         set: { draft.players[service.unit] = $0 })) {
                        Text(verbatim: service.title)
                    }
                }
            } header: {
                InfoSectionHeader("Players", note: "Turning a player off stops it until you turn it on again or the machine restarts.")
            }
        }
    }
}

/// The Bluetooth receiver and pairing
struct AudioHubBluetoothSection: View {
    let state: AudioHubState
    @Binding var draft: AudioHubDraft
    let run: (String, String) -> Void

    var body: some View {
        Section {
            Toggle("Bluetooth", isOn: Binding(get: { draft.bluetooth ?? state.bluetoothPowered },
                                               set: { draft.bluetooth = $0 }))
            if state.bluetoothPowered {
                Button("Pair a phone", systemImage: "iphone.radiowaves.left.and.right") { run("/bluetooth/pairing_mode", "") }
                    .disabled(state.bluetoothPairing)
                if state.bluetoothPairing {
                    Text("Open Bluetooth on your phone and pick this machine.").foregroundStyle(.secondary)
                }
            }
        } header: {
            InfoSectionHeader("Bluetooth", note: "Phones play through this machine over Bluetooth. Pairing stays open for a short while; a phone paired once reconnects on its own.")
        }
    }
}

/// Hub settings that wait to be applied
struct AudioHubDraft: Equatable {
    var output: String?
    var players: [String: Bool] = [:]
    var bluetooth: Bool?

    /// The hub calls that make the state match
    func calls(against state: AudioHubState) -> [String] {
        var calls: [String] = []
        if let output, output != state.defaultOutput { calls.append("/audio/outputs/\(output)/default") }
        for service in state.services {
            guard let on = players[service.unit], on != service.running else { continue }
            calls.append("/services/user/\(service.unit)/\(on ? "start" : "stop")")
        }
        if let bluetooth, bluetooth != state.bluetoothPowered {
            calls.append(bluetooth ? "/bluetooth/power_up" : "/bluetooth/power_down")
        }
        return calls
    }
}

extension AudioHubState {
    var defaultOutput: String { outputs.first(where: \.isDefault)?.name ?? "" }
}
