import Foundation

/// Stops waiting for slow work after a limit
enum Deadline {
    /// The work's result, or `fallback` when the limit passes first
    static func run<T: Sendable>(_ limit: Duration, fallback: T,
                                 _ work: @escaping @Sendable () async -> T) async -> T {
        await withCheckedContinuation { continuation in
            let once = OnceResumer(continuation)
            Task { once.resume(await work()) }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(fallback)
            }
        }
    }
}

/// Resumes a continuation on the first call
private final class OnceResumer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
