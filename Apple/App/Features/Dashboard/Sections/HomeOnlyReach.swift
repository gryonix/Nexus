import Foundation
import SwiftUI

/// Whether a home-only site opens from here
enum HomeOnlyReach: Equatable {
    case checking, opens, closedHere

    /// A guard refusal or no answer means not from here
    static func check(host: String) async -> HomeOnlyReach {
        guard let url = URL(string: "https://\(host)/") else { return .closedHere }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .closedHere }
        return status == 403 ? .closedHere : .opens
    }
}

/// One line saying whether the site opens from here
struct HomeOnlyReachLine: View {
    let host: String
    @State private var reach = HomeOnlyReach.checking

    var body: some View {
        Group {
            switch reach {
            case .checking: Text("Checking from here…").foregroundStyle(.secondary)
            case .opens: Text("Opens from here ✓").foregroundStyle(.green)
            case .closedHere: Text("Not reachable from here: only at home or over our VPN.").foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .padding(.leading, 16)
        .task(id: host) { reach = await HomeOnlyReach.check(host: host) }
    }
}
