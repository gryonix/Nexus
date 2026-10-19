import SwiftUI
import gryonixNexusCore

struct TechnicalField: View {
    let title: LocalizedStringKey
    let prompt: String
    @Binding var text: String
    var ownAddress = false
    @ObservedObject private var license = LicenseStore.shared

    var body: some View {
        if ownAddress && !license.status.isActive {
            lockedRow
        } else {
            editableRow
        }
    }

    private var lockedRow: some View {
        Button { LicensePrompt.shared.allow() } label: {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    Text(verbatim: text.isEmpty ? prompt : text)
                    Image(systemName: "lock.fill")
                }
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var editableRow: some View {
        #if os(macOS)
        LabeledContent(title) { field() }
        #else
        AdaptiveRow(title) { stacked in
            if stacked {
                field(alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                field(alignment: .trailing).frame(minWidth: 100, idealWidth: 120, maxWidth: 200)
            }
        }
        #endif
    }

    @ViewBuilder private func field(alignment: TextAlignment = .trailing) -> some View {
        #if os(macOS)
        TextField(title, text: $text)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.primary)
            .autocorrectionDisabled()
            .overlay(alignment: .trailing) {
                if text.isEmpty {
                    Text(verbatim: prompt)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
        #else
        TextField(title, text: $text, prompt: Text(verbatim: prompt).foregroundStyle(.secondary))
            .labelsHidden()
            .multilineTextAlignment(alignment)
            .foregroundStyle(.primary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
        #endif
    }
}

/// SecureField sibling of TechnicalField — for passwords entered in forms
struct SecureTechnicalField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            SecureField(title, text: $text)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
        }
    }
}

/// Server distribution picker
struct DistributionPicker: View {
    var title: LocalizedStringKey = "Server distribution"
    @Binding var selection: DistributionProfileID

    var body: some View {
        WrappingPicker(title, selection: $selection) {
            Text("Debian").tag(DistributionProfileID.debian)
            Text("Ubuntu").tag(DistributionProfileID.ubuntu)
        }
    }
}
