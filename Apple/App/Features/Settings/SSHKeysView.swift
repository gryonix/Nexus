import ServerControl
import SwiftUI

/// Settings, Security, SSH keys
struct SSHKeysView: View {
    @ObservedObject private var store = UserSSHKeyStore.shared
    @State private var generating = false
    @State private var busy = false

    var body: some View {
        CardList {
            Section {
                if store.keys.isEmpty {
                    Text("No keys yet.").foregroundStyle(.secondary)
                }
                ForEach(store.keys) { key in
                    NavigationLink {
                        SSHKeyDetailView(keyID: key.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.name)
                            Text("\(key.kind.displayName)  \(key.fingerprint)")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            } footer: {
                Text("Ed25519 is the recommended type. Private keys stay encrypted on this device. Nothing is installed on a server until you choose it.")
            }
            Section {
                ForEach(SSHKeyKind.allCases, id: \.self) { kind in
                    Button { Task { await generate(kind) } } label: {
                        Text("Generate \(kind.displayName)")
                    }
                    .disabled(busy)
                }
            }
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .screenTitle("SSH keys")
        .overlay { if busy { ProgressView() } }
    }

    private func generate(_ kind: SSHKeyKind) async {
        busy = true
        defer { busy = false }
        let name = SSHKeyNaming.nextName(kind: kind, existing: store.keys.map(\.name))
        let key = await Task.detached { try? SSHKeyGenerator.generate(kind: kind, name: name) }.value
        if let key { store.add(key) }
    }
}

/// Default names for new keys
enum SSHKeyNaming {
    static func nextName(kind: SSHKeyKind, existing: [String]) -> String {
        let base = kind.displayName
        guard existing.contains(base) else { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
