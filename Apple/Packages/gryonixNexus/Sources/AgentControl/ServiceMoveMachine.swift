import Foundation
import ServiceCatalog

public typealias ServiceMoveLog = @Sendable (String) -> Void

public struct ServiceMoveArchive: Sendable, Equatable {
    public let path: String
    public let name: String
    public let bytes: Int64

    public init(path: String, name: String, bytes: Int64) {
        self.path = path
        self.name = name
        self.bytes = bytes
    }
}

public struct ServiceMoveGrant: Sendable, Equatable {
    public let authorizedKeyLine: String
    public let hostKeys: String
    public let freeBytes: Int64

    public init(authorizedKeyLine: String, hostKeys: String, freeBytes: Int64) {
        self.authorizedKeyLine = authorizedKeyLine
        self.hostKeys = hostKeys
        self.freeBytes = freeBytes
    }
}

public struct ServiceMoveSent: Sendable, Equatable {
    public let bytes: Int64
    public let sha256: String
    public let archiveName: String

    public init(bytes: Int64, sha256: String, archiveName: String) {
        self.bytes = bytes
        self.sha256 = sha256
        self.archiveName = archiveName
    }
}

/// How the front proxies one service
public enum ServiceMoveSite: Sendable, Equatable {
    case local
    case remote(String)
    case missing
    case unknown
}

public struct ServiceMoveSiteChange: Sendable, Equatable {
    public var service: ServiceID
    public var localPort: UInt32
    public var localHTTPS: Bool
    public var overwriteForwardedFor: Bool
    /// `nil` serves the site from the front itself
    public var remoteAddress: String?
    public var dryRun: Bool

    public init(service: ServiceID, localPort: UInt32, localHTTPS: Bool, overwriteForwardedFor: Bool,
                remoteAddress: String?, dryRun: Bool = false) {
        self.service = service
        self.localPort = localPort
        self.localHTTPS = localHTTPS
        self.overwriteForwardedFor = overwriteForwardedFor
        self.remoteAddress = remoteAddress
        self.dryRun = dryRun
    }
}

public struct ServiceMoveProbe: Sendable, Equatable {
    public let answered: Bool
    public let unavailable: Bool
    public let status: Int32
    public let detail: String

    public init(answered: Bool, unavailable: Bool, status: Int32, detail: String) {
        self.answered = answered
        self.unavailable = unavailable
        self.status = status
        self.detail = detail
    }
}

public protocol ServiceMoveMachine: Sendable {
    func hasService(_ service: ServiceID) async throws -> Bool
    func estimatedBytes(of service: ServiceID) async throws -> Int64
    func install(_ service: ServiceID, context: AgentInstallContext, log: @escaping ServiceMoveLog) async throws
    func backUp(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws -> ServiceMoveArchive
    func start(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws
    func stop(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws
    func restore(_ service: ServiceID, archivePath: String, log: @escaping ServiceMoveLog) async throws
    func removeCopy(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws
    func deleteBackup(_ service: ServiceID, path: String) async throws

    func prepareSend(transferID: String) async throws -> String
    func prepareReceive(transferID: String, service: ServiceID, publicKey: String,
                        expectedBytes: Int64) async throws -> ServiceMoveGrant
    func authorize(_ grant: ServiceMoveGrant) async throws
    func revoke(transferID: String) async throws
    func send(transferID: String, service: ServiceID, archivePath: String, to target: ServiceMoveEndpoint,
              hostKeys: String, log: @escaping ServiceMoveLog) async throws -> ServiceMoveSent
    func accept(transferID: String, service: ServiceID, sent: ServiceMoveSent,
                log: @escaping ServiceMoveLog) async throws -> String
    func discard(transferID: String) async throws

    func site(_ change: ServiceMoveSiteChange) async throws -> ServiceMoveSite
    func probe(_ service: ServiceID) async throws -> ServiceMoveProbe
}

/// Where the old machine dials the new one
public struct ServiceMoveEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt32
    public let user: String

    public init(host: String, port: UInt32, user: String) {
        self.host = host
        self.port = port
        self.user = user
    }
}

public protocol ServiceMoveShell: Sendable {
    var loginUser: String { get }
    func appendAuthorizedKey(_ line: String) async throws
    func removeAuthorizedKeys(containing marker: String) async throws
}
