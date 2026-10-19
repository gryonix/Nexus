/// A disk as the app saw it
public struct DiskIdentity: Sendable, Hashable {
    public let path: String
    public let serial: String
    public let sizeBytes: Int64

    public init(path: String, serial: String, sizeBytes: Int64) {
        self.path = path
        self.serial = serial
        self.sizeBytes = sizeBytes
    }
}

extension ServerDisk {
    public var identity: DiskIdentity {
        DiskIdentity(path: path, serial: serial.filter { !$0.isWhitespace }, sizeBytes: sizeBytes)
    }
}
