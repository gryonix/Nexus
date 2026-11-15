import Foundation
import Network

/// An Apple TV running Nexus on this network
public struct TVNearby: Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    public let tvID: String?
    public let endpoint: NWEndpoint
    /// When the TV app last said it is on screen
    public let awakeAt: Date?

    public var id: String { tvID ?? name }

    public init(name: String, tvID: String?, endpoint: NWEndpoint, awakeAt: Date? = nil) {
        self.name = name
        self.tvID = tvID
        self.endpoint = endpoint
        self.awakeAt = awakeAt
    }

    /// A sleeping TV's record keeps an old time
    public func isAwake(now: Date) -> Bool {
        guard let awakeAt else { return false }
        return abs(now.timeIntervalSince(awakeAt)) <= TVLinkService.awakeFreshness
    }
}

/// Watches the local network for TVs, over Bonjour
public final class TVBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.skaymer.gryonixnexus.tvlink.browser")
    private var browser: NWBrowser?
    private let onChange: @Sendable ([TVNearby]) -> Void

    public init(onChange: @escaping @Sendable ([TVNearby]) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: TVLinkService.type, domain: nil),
                                using: parameters)
        browser.browseResultsChangedHandler = { [onChange] results, _ in
            onChange(results.compactMap(Self.nearby).sorted { $0.name < $1.name })
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    static func nearby(_ result: NWBrowser.Result) -> TVNearby? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        guard case .bonjour(let record) = result.metadata else {
            return TVNearby(name: name, tvID: nil, endpoint: result.endpoint)
        }
        return TVNearby(name: name, tvID: record[TVLinkService.idKey], endpoint: result.endpoint,
                        awakeAt: awakeTime(record[TVLinkService.awakeKey]))
    }

    static func awakeTime(_ text: String?) -> Date? {
        guard let text, let seconds = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
