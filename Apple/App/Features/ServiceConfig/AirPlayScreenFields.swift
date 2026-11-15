import SwiftUI

/// The AirPlay screen's name and the DRM limit
struct AirPlayScreenFields: View {
    @Binding var name: String

    var body: some View {
        TechnicalField(title: "Screen name", prompt: "gryonix TV", text: $name, spokenName: true)
        Label("DRM-protected video (Netflix and similar) cannot be shown — that is an Apple restriction.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
