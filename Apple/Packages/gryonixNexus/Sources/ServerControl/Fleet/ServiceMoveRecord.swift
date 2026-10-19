import Foundation
import ServiceCatalog

/// The stages of a move, in the order they run
public enum ServiceMoveStep: Int, Codable, Sendable, CaseIterable, Comparable {
    case check
    case install
    case backup
    case stop
    case send
    case restore
    case switchEntry
    case verify
    case finish

    public static func < (lhs: ServiceMoveStep, rhs: ServiceMoveStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ServiceMoveRecord: Codable, Sendable, Equatable {
    public var deployment: UUID
    public var service: ServiceID
    public var source: UUID
    public var target: UUID
    public var step: ServiceMoveStep
    public var transferID: String
    public var installedOnTarget: Bool
    public var sourceStopped: Bool
    public var switchedEntry: Bool
    public var archivePath: String?
    public var archiveName: String?
    public var archiveBytes: Int64?
    public var sha256: String?
    public var sentBytes: Int64?
    public var targetArchivePath: String?
    public var started: Date

    public init(deployment: UUID, service: ServiceID, source: UUID, target: UUID,
                transferID: String, started: Date = Date()) {
        self.deployment = deployment
        self.service = service
        self.source = source
        self.target = target
        self.step = .check
        self.transferID = transferID
        self.installedOnTarget = false
        self.sourceStopped = false
        self.switchedEntry = false
        self.started = started
    }
}
