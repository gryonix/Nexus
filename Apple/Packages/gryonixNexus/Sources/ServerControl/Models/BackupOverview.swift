import Foundation

/// One backup with the server and service it belongs to
public struct FleetBackup: Identifiable, Sendable, Hashable {
    public let serverID: UUID
    public let serverName: String
    public let serviceID: String
    public let serviceName: String
    public let entry: BackupEntry

    public init(serverID: UUID, serverName: String, serviceID: String, serviceName: String,
                entry: BackupEntry) {
        self.serverID = serverID
        self.serverName = serverName
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.entry = entry
    }

    public var id: String { "\(serverID)/\(serviceID)/\(entry.drive ?? "")/\(entry.name)" }
}

/// Which backups a list shows
public struct BackupFilter: Sendable, Equatable {
    public enum Place: Sendable, Equatable {
        case any, server, drives

        public func admits(_ entry: BackupEntry) -> Bool {
            switch self {
            case .any: return true
            case .server: return entry.drive == nil
            case .drives: return entry.drive != nil
            }
        }
    }

    public var serviceID: String?
    public var place: Place = .any

    public init(serviceID: String? = nil, place: Place = .any) {
        self.serviceID = serviceID
        self.place = place
    }

    public func admits(_ row: FleetBackup) -> Bool {
        if let serviceID, row.serviceID != serviceID { return false }
        return place.admits(row.entry)
    }
}

/// Counts and sizes over a set of backups
public struct BackupTotals: Sendable, Equatable {
    public var count = 0
    public var bytes: Int64 = 0
    public var onDrives = 0
    public var newest: Date?
    /// Backups without a known size
    public var unsized = 0

    public init() {}
}

public enum BackupOverview {
    /// Newest first; undated ones stay last
    public static func sorted(_ rows: [FleetBackup]) -> [FleetBackup] {
        rows.enumerated().sorted { left, right in
            switch (left.element.entry.modifiedAt, right.element.entry.modifiedAt) {
            case let (a?, b?): return a != b ? a > b : left.offset < right.offset
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return left.offset < right.offset
            }
        }.map(\.element)
    }

    public static func filtered(_ rows: [FleetBackup], by filter: BackupFilter) -> [FleetBackup] {
        rows.filter(filter.admits)
    }

    public static func totals(_ rows: [FleetBackup]) -> BackupTotals {
        var totals = BackupTotals()
        for row in rows {
            totals.count += 1
            if row.entry.drive != nil { totals.onDrives += 1 }
            if let size = row.entry.sizeBytes { totals.bytes += size } else if !row.entry.isDirectory {
                totals.unsized += 1
            }
            if let date = row.entry.modifiedAt, date > (totals.newest ?? .distantPast) {
                totals.newest = date
            }
        }
        return totals
    }
}
