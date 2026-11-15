import ServerControl
import SwiftUI

/// Settings of the hub's Spotify, AirPlay and music library players
struct AudioHubSourcesSections: View {
    let saved: AudioHubSources
    @Binding var draft: AudioHubSources

    var body: some View {
        if saved.hasSpotify {
            player("spotify", header: "Spotify", rows: AudioHubPlayerCatalog.spotify,
                   footer: "How this machine appears in Spotify and how it plays. Applying restarts the Spotify player; music pauses for a few seconds.")
        }
        if saved.hasAirPlay {
            player("airplay", header: "AirPlay", rows: AudioHubPlayerCatalog.airPlay,
                   footer: "The name this machine shows in the AirPlay list. Applying restarts the AirPlay speaker.")
        }
        if saved.hasLibrary {
            player("mpd", header: "MPD", rows: AudioHubPlayerCatalog.library,
                   footer: "The music library on this machine, as MPD apps on your phone or computer see it. Applying restarts the library player.")
        }
    }

    private func player(_ prefix: String, header: String, rows: [SpeakerSetting], footer: LocalizedStringKey) -> some View {
        Section {
            TechnicalField(title: "Speaker name", prompt: saved.values["\(prefix).name"] ?? "",
                           text: text("\(prefix).name"), spokenName: true)
            ForEach(rows) { SpeakerSettingRow(setting: $0, values: values(prefix)) }
        } header: {
            Text(verbatim: header)
        } footer: {
            Text(footer)
        }
    }

    private func text(_ id: String) -> Binding<String> {
        Binding(get: { draft.values[id] ?? "" }, set: { draft.values[id] = $0 })
    }

    /// One player's values without its prefix
    private func values(_ prefix: String) -> Binding<[String: String]> {
        let lead = "\(prefix)."
        return Binding(
            get: {
                Dictionary(uniqueKeysWithValues: draft.values.compactMap { id, value in
                    id.hasPrefix(lead) ? (String(id.dropFirst(lead.count)), value) : nil
                })
            },
            set: { fresh in
                for (key, value) in fresh { draft.values[lead + key] = value }
            })
    }
}
