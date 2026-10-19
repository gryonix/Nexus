import AgentClient
import SwiftUI

struct DynamicDNSSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var zone = ""
    @State private var names = ""
    @State private var token = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Zone", text: $zone, prompt: Text("example.com"))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    InfoSectionHeader("Zone", note: "The domain this token may edit.")
                }

                Section {
                    TextEditor(text: $names)
                        .frame(minHeight: 88)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    InfoSectionHeader("Names", note: "One name per line. Each must already exist as an A record.")
                }

                Section {
                    SecureField("API token", text: $token,
                                prompt: Text(state?.hasToken_p == true
                                             ? "Stored on the server"
                                             : "Cloudflare API token"))
                } header: {
                    InfoSectionHeader("API token") {
                        Text("A token scoped to edit DNS for this zone. It is stored on the server, readable only by root, and never sent back to this device.")
                        if state?.hasToken_p == true {
                            Text("The server already holds one — leave the field empty to keep it.")
                        }
                    }
                }

                recentSection

                statusSection
            }
            .navigationTitle(Text("Dynamic DNS"))
            .raisedNavigationTitle()
            .disabled(isWorking)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(names: enteredNames) }
                        .disabled(!canSave)
                }
            }
            .task {
                await viewModel.loadDynamicDNS()
                if zone.isEmpty { zone = state?.zone ?? "" }
                if names.isEmpty { names = (state?.names ?? []).joined(separator: "\n") }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if let recent = state?.recent, !recent.isEmpty {
            Section {
                ForEach(recent.reversed(), id: \.self) { line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } header: {
                InfoSectionHeader("Recent checks", note: "Written by the server itself, whether or not this app is running.")
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if state?.enabled == true {
            Section {
                Button(role: .destructive) {
                    save(names: [])
                } label: {
                    Text("Stop updating")
                }
                .rowActionButtonStyle()
                .dangerTint()
            } footer: {
                Text("The server stops checking and forgets the stored token.")
            }
        }
    }

    private var state: Gryonixnexusd_V1_DynamicDNSState? { viewModel.dynamicDNS }

    private var enteredNames: [String] {
        names.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        guard !zone.trimmingCharacters(in: .whitespaces).isEmpty, !enteredNames.isEmpty else { return false }
        return state?.hasToken_p == true || !token.isEmpty
    }

    private func save(names: [String]) {
        isWorking = true
        Task {
            await viewModel.setDynamicDNS(zone: zone.trimmingCharacters(in: .whitespaces),
                                          names: names,
                                          token: token)
            isWorking = false
            dismiss()
        }
    }
}
