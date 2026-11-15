import Foundation

/// What a tap on a server alert opens
enum AlertTap: Equatable {
    case run(jobID: String, fallback: AlertDestination?, card: AlertCard?)
    case card(AlertDestination, AlertCard)
    case server(AlertDestination)
    case nothing

    init(gnx: [String: Any], title: String, body: String,
         deploymentID: (String) -> UUID? = { RelayServers.deploymentID(of: $0) }) {
        let destination = AlertDestination(gnx: gnx, deploymentID: deploymentID)
        let card = AlertCard(gnx: gnx, title: title, body: body)
        if let jobID = gnx["job_id"] as? String, !jobID.isEmpty {
            self = .run(jobID: jobID, fallback: destination, card: card)
        } else if let destination, let card {
            self = .card(destination, card)
        } else if let destination {
            self = .server(destination)
        } else {
            self = .nothing
        }
    }
}
