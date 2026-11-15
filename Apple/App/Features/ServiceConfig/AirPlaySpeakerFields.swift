import SwiftUI

/// The AirPlay speaker's version and name before it is installed
struct AirPlaySpeakerFields: View {
    @Binding var mode: String
    @Binding var name: String

    var body: some View {
        WrappingPicker("AirPlay version", selection: $mode) {
            Text(verbatim: "AirPlay 2").tag("airplay2")
            Text(verbatim: "AirPlay 1").tag("airplay1")
        }
        Label("AirPlay 2 joins HomePod and multi-room; AirPlay 1 works with every Apple device and allows track control. Switching restarts the speaker; music pauses for a few seconds.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
        TechnicalField(title: "Speaker name", prompt: "gryonix", text: $name, spokenName: true)
        Label("The sound output, volume and timing are chosen after installing, in the speaker's settings.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
