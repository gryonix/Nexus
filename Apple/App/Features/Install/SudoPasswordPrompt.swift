import SwiftUI

/// Asks a non-root account's password once for administrator access
struct SudoPasswordPrompt: View {
    let username: String
    let error: String?
    let isWorking: Bool
    let onSubmit: (String) -> Void

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: UIL10n.string(
                "%@ needs administrator rights. Enter its password once: the app sets up access by itself and does not keep the password.",
                username))
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Account password", text: $password)
                .textContentType(.password)
                .onSubmit(submit)
                .accessibilityIdentifier("sudo.password")
            HStack {
                Button("Allow", action: submit)
                    .rowActionButtonStyle()
                    .disabled(password.isEmpty || isWorking)
                    .accessibilityIdentifier("sudo.allow")
                if isWorking { ProgressView().controlSize(.small) }
            }
            if let error {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        guard !password.isEmpty, !isWorking else { return }
        onSubmit(password)
        password = ""
    }
}
