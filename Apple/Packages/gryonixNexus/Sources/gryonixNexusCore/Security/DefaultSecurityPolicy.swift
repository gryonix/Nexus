/// Concrete secure default values.
public struct DefaultSecurityPolicy: SecurityPolicy {
    public let minimumTLSVersion: TLSVersion = .v1_2
    public let dkimKeyBits: Int = 2048
    public let allowOpenRelay: Bool = false
    public let ssh = SSHHardening()

    public init() {}
}
