import AgentClient
import SwiftUI

struct AirPlayOutputPicker: View {
    let outputs: [Gryonixnexusd_V1_AudioOutput]
    let error: String?
    @Binding var output: String
    @Binding var mixer: String

    var body: some View {
        if outputs.isEmpty {
            HStack {
                Text("Sound output")
                InfoNote("Sound output", "The sound card the music plays through, as this machine reports it.")
                Spacer()
                if error == nil { ProgressView() } else { Text(verbatim: output).foregroundStyle(.secondary) }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Picker("Sound output", selection: $output) {
                ForEach(choices, id: \.device) { item in
                    Text(label(item)).tag(item.device)
                }
            }
            .infoNote("Sound output", "The sound card the music plays through, as this machine reports it.")
            Picker("Volume control", selection: $mixer) {
                Text("Software").tag("")
                ForEach(mixers, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .infoNote("Volume control", "Lets the phone move the sound card's own volume. Software scales the sound inside the speaker instead, which works with every card.")
        }
    }

    private var choices: [Gryonixnexusd_V1_AudioOutput] {
        guard !outputs.contains(where: { $0.device == output }) else { return outputs }
        var saved = Gryonixnexusd_V1_AudioOutput()
        saved.device = output
        return outputs + [saved]
    }

    private var mixers: [String] {
        let own = outputs.first { $0.device == output }?.mixers ?? []
        return mixer.isEmpty || own.contains(mixer) ? own : own + [mixer]
    }

    private func label(_ item: Gryonixnexusd_V1_AudioOutput) -> String {
        if item.device == "default" { return UIL10n.string("System default") }
        return item.title.isEmpty ? item.device : item.title
    }
}
