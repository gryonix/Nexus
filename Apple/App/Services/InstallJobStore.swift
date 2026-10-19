import Foundation
import ServiceCatalog

struct StoredInstallJob: Codable, Hashable, Identifiable {
    var deploymentID: UUID
    var serviceID: String
    var jobID: String
    var startedAt: Date

    var id: String { "\(deploymentID.uuidString)-\(serviceID)" }
}

struct InstallJobStore {
    static let key = "install-jobs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [StoredInstallJob] {
        guard let data = defaults.data(forKey: Self.key),
              let jobs = try? JSONDecoder().decode([StoredInstallJob].self, from: data) else {
            return []
        }
        return jobs
    }

    func job(deployment: UUID, service: ServiceID) -> StoredInstallJob? {
        load().first { $0.deploymentID == deployment && $0.serviceID == service.rawValue }
    }

    /// Everything this device is still waiting on for one deployment
    func jobs(deployment: UUID) -> [StoredInstallJob] {
        load().filter { $0.deploymentID == deployment }
    }

    func remember(deployment: UUID, service: ServiceID, jobID: String) {
        var jobs = load().filter {
            !($0.deploymentID == deployment && $0.serviceID == service.rawValue)
        }
        jobs.append(StoredInstallJob(deploymentID: deployment,
                                     serviceID: service.rawValue,
                                     jobID: jobID,
                                     startedAt: Date()))
        write(jobs)
    }

    /// Marks services as waiting their turn, unless already recorded
    func queue(deployment: UUID, services: [ServiceID]) {
        var jobs = load()
        for service in services where !jobs.contains(where: {
            $0.deploymentID == deployment && $0.serviceID == service.rawValue
        }) {
            jobs.append(StoredInstallJob(deploymentID: deployment, serviceID: service.rawValue,
                                         jobID: "", startedAt: Date()))
        }
        write(jobs)
    }

    /// Forget a run that has ended
    func forget(deployment: UUID, service: ServiceID) {
        write(load().filter {
            !($0.deploymentID == deployment && $0.serviceID == service.rawValue)
        })
    }

    func forget(deployment: UUID, rawService: String) {
        write(load().filter { !($0.deploymentID == deployment && $0.serviceID == rawService) })
    }

    /// Drop everything belonging to a deployment
    func forgetAll(deployment: UUID) {
        write(load().filter { $0.deploymentID != deployment })
    }

    private func write(_ jobs: [StoredInstallJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
