import Foundation

/// Per-session traffic split and the in-memory request log.

public struct AdvancedTraffic: Codable, Equatable, Sendable {
    public struct Counter: Codable, Equatable, Sendable {
        public var uploaded: Int64 = 0
        public var downloaded: Int64 = 0

        public init(uploaded: Int64 = 0, downloaded: Int64 = 0) {
            self.uploaded = uploaded
            self.downloaded = downloaded
        }

        public var total: Int64 { uploaded + downloaded }
    }

    public struct Request: Codable, Equatable, Sendable, Identifiable {
        public var id: String { "\(time.timeIntervalSince1970)-\(domain)-\(route)" }
        public let time: Date
        public let domain: String
        /// The outbound that took it: proxy, direct or block
        public let route: String

        public init(time: Date, domain: String, route: String) {
            self.time = time
            self.domain = domain
            self.route = route
        }
    }

    public var direct = Counter()
    public var proxy = Counter()
    public var requests: [Request] = []

    public init() {}

    public static let requestLimit = 200

    public static let request = Data("advanced-traffic".utf8)

    /// Reads xray's metrics answer: outbound counters by tag
    public static func counters(fromMetrics json: Data) -> AdvancedTraffic {
        var traffic = AdvancedTraffic()
        let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let outbound = (root?["stats"] as? [String: Any])?["outbound"] as? [String: [String: Any]] ?? [:]
        for (tag, values) in outbound {
            var counter = Counter()
            counter.uploaded = Int64("\(values["uplink"] ?? 0)") ?? 0
            counter.downloaded = Int64("\(values["downlink"] ?? 0)") ?? 0
            if tag == "direct" {
                traffic.direct = counter
            } else if tag == "proxy" || tag.hasPrefix("s") {
                traffic.proxy.uploaded += counter.uploaded
                traffic.proxy.downloaded += counter.downloaded
            }
        }
        return traffic
    }

    /// Reads xray access-log lines into requests, newest last
    public static func requests(fromLog text: String) -> [Request] {
        let parsed = text.split(whereSeparator: \.isNewline).compactMap { request(fromLine: String($0)) }
        return Array(parsed.suffix(requestLimit))
    }

    static func request(fromLine line: String) -> Request? {
        guard let accepted = line.range(of: " accepted "), let open = line.lastIndex(of: "["),
              let close = line.lastIndex(of: "]"), open < close else { return nil }
        let stamp = String(line[..<line.index(line.startIndex, offsetBy: min(19, line.count))])
        let target = line[accepted.upperBound..<open].trimmingCharacters(in: .whitespaces)
        let route = line[line.index(after: open)..<close].components(separatedBy: "->").last?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let hostPort = target.split(separator: ":", maxSplits: 1).last.map(String.init) ?? target
        let domain = hostPort.lastIndex(of: ":").map { String(hostPort[..<$0]) } ?? hostPort
        guard !domain.isEmpty else { return nil }
        return Request(time: formatter.date(from: stamp) ?? Date(), domain: domain,
                       route: route.hasPrefix("s") && route != "socks-in" ? "proxy" : route)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
