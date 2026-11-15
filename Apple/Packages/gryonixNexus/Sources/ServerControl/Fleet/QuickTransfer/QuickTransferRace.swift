import Foundation

/// The first link to connect wins; the rest close
public enum QuickTransferRace {
    public typealias Attempt = @Sendable () async throws -> any QuickTransferLink

    public static func first(of attempts: [Attempt], timeout: TimeInterval) async throws -> any QuickTransferLink {
        try await withThrowingTaskGroup(of: (any QuickTransferLink)?.self) { group in
            for attempt in attempts {
                group.addTask { try? await attempt() }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw QuickTransferError.timedOut
            }
            var winner: (any QuickTransferLink)?
            var failures = 0
            while winner == nil, let result = try await group.next() {
                if let result { winner = result } else { failures += 1 }
                if winner == nil, failures == attempts.count { throw QuickTransferError.closed }
            }
            group.cancelAll()
            await closeLosers(in: &group)
            guard let winner else { throw QuickTransferError.closed }
            return winner
        }
    }

    private static func closeLosers(in group: inout ThrowingTaskGroup<(any QuickTransferLink)?, Error>) async {
        while true {
            do {
                guard let late = try await group.next() else { return }
                late?.close()
            } catch {
                continue
            }
        }
    }
}
