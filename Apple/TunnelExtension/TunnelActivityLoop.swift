import Foundation
import VPNProfile

/// Moves the session card while the tunnel runs
final class TunnelActivityLoop: @unchecked Sendable {
    typealias Measure = (@escaping (TunnelActivityFeed.Sample) -> Void) -> Void

    private let relay = TunnelActivityRelay()
    private let queue = DispatchQueue(label: "tunnel.activity")
    private var feed = TunnelActivityFeed()
    private var timer: DispatchSourceTimer?
    private var lastSample: TunnelActivityFeed.Sample?

    func start(measure: @escaping Measure) {
        #if os(iOS)
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 5, repeating: .seconds(10))
        source.setEventHandler { measure { [weak self] sample in self?.offer(sample) } }
        source.resume()
        timer = source
        #endif
    }

    private func offer(_ sample: TunnelActivityFeed.Sample) {
        queue.async { [self] in
            lastSample = sample
            guard let ticket = TunnelActivityTicket.load(),
                  let body = feed.next(sample, ticket: ticket, now: Date()) else { return }
            Task { await relay.send(body, ticket: ticket) }
        }
    }

    /// Closes the card, waiting at most three seconds
    func stop(_ done: @escaping () -> Void) {
        timer?.cancel()
        timer = nil
        queue.async { [self] in
            guard let ticket = TunnelActivityTicket.load(), let sample = lastSample else { return done() }
            let body = feed.end(sample, ticket: ticket, now: Date())
            TunnelActivityTicket.clear()
            let once = Once(done)
            Task { await relay.send(body, ticket: ticket); once.run() }
            queue.asyncAfter(deadline: .now() + 3) { once.run() }
        }
    }
}

/// Runs a closure the first time only
private final class Once: @unchecked Sendable {
    private var work: (() -> Void)?
    private let lock = NSLock()

    init(_ work: @escaping () -> Void) { self.work = work }

    func run() {
        lock.lock()
        let pending = work
        work = nil
        lock.unlock()
        pending?()
    }
}
