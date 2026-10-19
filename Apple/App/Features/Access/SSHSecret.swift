import Foundation
import ServerControlSSH
import SwiftUI

enum SSHSecret: Codable, Hashable, Sendable {
    case password(String)
    case privateKeySeed(Data)
    /// This deployment's own app key
    case appKey

    /// What a list shows
    var kindDescription: String {
        switch self {
        case .password: return "Password"
        case .privateKeySeed: return "Private key"
        case .appKey: return "This app's key"
        }
    }
}

/// The form half of the question above
struct SSHSecretDraft {
    enum Kind: String, CaseIterable, Identifiable {
        case appKey, password, privateKey
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .appKey: return "This app's key"
            case .password: return "Password"
            case .privateKey: return "Private key"
            }
        }
    }

    var kind: Kind
    var password = ""
    var pastedKey = ""
    var problem: String?

    init(kind: Kind = .appKey) {
        self.kind = kind
    }

    /// Fills the draft from a secret being edited
    init(editing secret: SSHSecret) {
        switch secret {
        case .appKey:
            self.init(kind: .appKey)
        case .password(let value):
            self.init(kind: .password)
            password = value
        case .privateKeySeed:
            self.init(kind: .privateKey)
        }
    }

    var isComplete: Bool {
        switch kind {
        case .appKey: return true
        case .password: return !password.isEmpty
        case .privateKey: return !pastedKey.isEmpty
        }
    }

    mutating func secret(keeping existing: SSHSecret? = nil) -> SSHSecret? {
        switch kind {
        case .appKey:
            return .appKey
        case .password:
            return .password(password)
        case .privateKey:
            if pastedKey.isEmpty, case .privateKeySeed(let seed)? = existing {
                return .privateKeySeed(seed)
            }
            do {
                return .privateKeySeed(try TerminalLogin.seed(fromOpenSSHKey: pastedKey))
            } catch {
                problem = error.localizedDescription
                return nil
            }
        }
    }
}

/// The draft as a form section
struct SSHSecretSection: View {
    @Binding var draft: SSHSecretDraft
    var appKeyIsInstalled: Bool
    var appKeyFooter: LocalizedStringKey?

    var body: some View {
        Section {
            WrappingPicker("Sign in with", selection: $draft.kind) {
                ForEach(SSHSecretDraft.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            switch draft.kind {
            case .appKey:
                EmptyView()
            case .password:
                SecureField("Password", text: $draft.password)
            case .privateKey:
                TextEditor(text: $draft.pastedKey)
                    .font(.caption.monospaced())
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                if let problem = draft.problem {
                    Text(verbatim: problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            switch draft.kind {
            case .appKey:
                if let appKeyFooter {
                    Text(appKeyFooter)
                } else if appKeyIsInstalled {
                    Text("Works for any account that already has this app's public key. Nothing new is stored on this device.")
                } else {
                    Text("This machine does not have this app's key yet. Save the connection, then copy its public key into the account's authorized_keys — or sign in with a password.")
                }
            case .password:
                Text("Kept in the Keychain on this device.")
            case .privateKey:
                Text("Paste an OpenSSH ed25519 private key. Encrypted keys are not supported yet.")
            }
        }
    }
}
