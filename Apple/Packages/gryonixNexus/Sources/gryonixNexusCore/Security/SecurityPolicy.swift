/// Security policy consumed by the generators — so the rules
/// (no open relay, key sizes, TLS versions, SSH restrictions) live in one place,
/// rather than as scattered constants.
public protocol SecurityPolicy: Sendable {
    var minimumTLSVersion: TLSVersion { get }
    var dkimKeyBits: Int { get }
    var allowOpenRelay: Bool { get }             // always false by default
    var ssh: SSHHardening { get }
}

public enum TLSVersion: Sendable, Hashable {
    case v1_2, v1_3
}

public struct SSHHardening: Sendable, Hashable {
    public let permitRootLogin: Bool             // false
    public let passwordAuthentication: Bool      // false — keys only
    public let port: Int

    public init(permitRootLogin: Bool = false, passwordAuthentication: Bool = false, port: Int = 22) {
        self.permitRootLogin = permitRootLogin
        self.passwordAuthentication = passwordAuthentication
        self.port = port
    }
}
