import Foundation
#if os(iOS)
import ActivityKit
#endif

@MainActor
final class OperationActivities {
    static let shared = OperationActivities()

    /// The lock-screen card for each run, by the run's id
    #if os(iOS)
    private var live: [UUID: Activity<OperationActivityAttributes>] = [:]
    #endif

    private var offered: Set<UUID> = []

    init() {}

    /// True when the system will accept an activity at all
    var isAvailable: Bool {
        #if os(iOS)
        ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        false
        #endif
    }

    static let staleAfter: TimeInterval = 300

    func start(id: UUID, title: String, serverName: String, progressText: String,
               progress: Double? = nil, jobID: String? = nil, deploymentID: UUID? = nil,
               canStop: Bool = false) {
        guard !offered.contains(id) else { return }
        offered.insert(id)
        #if DEBUG
        LiveActivityProbe.note("start requested: \(title) available=\(isAvailable)")
        #endif
        #if os(iOS)
        guard isAvailable else { return }
        if let jobID, reclaim(jobID, for: id) { return }
        let attributes = OperationActivityAttributes(title: title,
                                                     serverName: serverName,
                                                     startedAt: Date(),
                                                     operationID: id,
                                                     canStop: canStop ? true : nil,
                                                     deploymentID: deploymentID)
        let state = OperationActivityAttributes.ContentState(progressText: progressText,
                                                             isFinished: false,
                                                             errorMessage: nil,
                                                             progress: progress)
        do {
            let activity = try Self.request(attributes, state: state, staleDate: staleDate)
            live[id] = activity
            followPushToken(of: activity, for: id)
            #if DEBUG
            LiveActivityProbe.note("accepted: \(live[id]?.id ?? "-")")
            #endif
        } catch {
            #if DEBUG
            LiveActivityProbe.note("refused: \(error)")
            #endif
        }
        #endif
    }

    #if os(iOS)
    /// Asks for a push token, falls back to local updates
    private static func request(_ attributes: OperationActivityAttributes,
                                state: OperationActivityAttributes.ContentState,
                                staleDate: Date) throws -> Activity<OperationActivityAttributes> {
        let content = ActivityContent(state: state, staleDate: staleDate)
        do {
            return try Activity.request(attributes: attributes, content: content, pushType: .token)
        } catch {
            return try Activity.request(attributes: attributes, content: content)
        }
    }

    private func followPushToken(of activity: Activity<OperationActivityAttributes>, for id: UUID) {
        Task {
            for await data in activity.pushTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                tokens[id] = token
                LiveActivityJobs.shared.tokenArrived(token, for: id)
            }
        }
    }
    #endif

    /// Push tokens of the cards started here
    private var tokens: [UUID: String] = [:]

    /// The card's push token, once it has one
    func pushToken(of id: UUID, waiting seconds: Double = 10) async -> String? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let token = tokens[id] { return token }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return tokens[id]
    }

    func update(id: UUID, progressText: String, progress: Double? = nil) {
        #if os(iOS)
        guard let activity = live[id] else { return }
        let state = OperationActivityAttributes.ContentState(progressText: progressText,
                                                             isFinished: false,
                                                             errorMessage: nil,
                                                             progress: progress,
                                                             stopArmed: armed.contains(id) ? true : nil)
        Task { await activity.update(.init(state: state, staleDate: staleDate)) }
        #if DEBUG
        LiveActivityProbe.note("updated: \(progressText) progress=\(progress.map { "\($0)" } ?? "-")")
        #endif
        #endif
    }

    /// When the CURRENT line stops being worth reading as news
    private var staleDate: Date { Date().addingTimeInterval(Self.staleAfter) }

    #if DEBUG
    func noteSystemState() {
        #if os(iOS)
        let known = Activity<OperationActivityAttributes>.activities
        LiveActivityProbe.note("system holds \(known.count) card(s): "
            + known.map { "\($0.id.prefix(8))=\($0.activityState)" }.joined(separator: ", ")
            + " | ours: "
            + live.values.map { "\($0.id.prefix(8))=\($0.activityState)" }.joined(separator: ", "))
        #endif
    }
    #endif

    /// How long a finished run stays on the lock screen
    static let finishedLingerSeconds: TimeInterval = 30
    /// A failure stays longer: it carries buttons
    static let failedLingerSeconds: TimeInterval = 3600

    /// Operations whose stop button waits for the second tap
    private(set) var armed: Set<UUID> = []

    /// Shows or clears the stop button's question
    func setStopArmed(_ isArmed: Bool, id: UUID) {
        if isArmed { armed.insert(id) } else { armed.remove(id) }
        #if os(iOS)
        guard let activity = card(for: id) else { return }
        var state = activity.content.state
        state.stopArmed = isArmed ? true : nil
        Task { await activity.update(.init(state: state, staleDate: staleDate)) }
        #endif
    }

    /// Says "Stopping…" on the card, even after a relaunch
    func showStopping(_ id: UUID) {
        #if os(iOS)
        guard let activity = card(for: id) else { return }
        var state = activity.content.state
        state.progressText = UIL10n.string("Stopping…")
        state.stopArmed = nil
        Task { await activity.update(.init(state: state, staleDate: staleDate)) }
        #endif
    }

    /// Whether the card asks "stop?", even after a relaunch
    func isStopArmed(_ id: UUID) -> Bool {
        #if os(iOS)
        if card(for: id)?.content.state.stopArmed == true { return true }
        #endif
        return armed.contains(id)
    }

    /// What the system card knows: its server, job and start
    func stopTarget(of id: UUID) -> (deploymentID: UUID?, jobID: String?, startedAt: Date)? {
        #if os(iOS)
        guard let activity = card(for: id) else { return nil }
        return (activity.attributes.deploymentID, Self.followedJobs()[activity.id], activity.attributes.startedAt)
        #else
        return nil
        #endif
    }

    #if os(iOS)
    /// Swaps this run's own card for the server's card
    func adoptRemote(_ activity: Activity<OperationActivityAttributes>) {
        guard let job = activity.attributes.jobID,
              let operation = LiveActivityJobs.shared.operation(following: job) else { return }
        take(activity, for: operation, job: job)
    }

    /// Moves a run onto its job's server card
    func adoptRemoteCard(of job: String, for operation: UUID) {
        guard let activity = Activity<OperationActivityAttributes>.activities.first(where: {
            $0.attributes.jobID == job && $0.activityState == .active
        }) else { return }
        take(activity, for: operation, job: job)
    }

    private func take(_ activity: Activity<OperationActivityAttributes>, for operation: UUID, job: String) {
        guard let own = live[operation], own.id != activity.id else { return }
        live[operation] = activity
        var followed = Self.followedJobs()
        followed[activity.id] = job
        Self.saveFollowedJobs(followed)
        Task { await own.end(own.content, dismissalPolicy: .immediate) }
    }

    /// A card a server started for this job
    func jobCard(_ job: String) -> Activity<OperationActivityAttributes>? {
        Activity<OperationActivityAttributes>.activities.first {
            $0.attributes.jobID == job && $0.activityState == .active
        }
    }

    /// Asks or clears "stop?" on a server-started card
    func setJobStopArmed(_ isArmed: Bool, job: String) {
        guard let activity = jobCard(job) else { return }
        var state = activity.content.state
        state.stopArmed = isArmed ? true : nil
        Task { await activity.update(.init(state: state, staleDate: staleDate)) }
    }

    func showStopping(job: String) {
        guard let activity = jobCard(job) else { return }
        var state = activity.content.state
        state.progressText = UIL10n.string("Stopping…")
        state.stopArmed = nil
        Task { await activity.update(.init(state: state, staleDate: staleDate)) }
    }

    /// This run's card, ours or one the system kept
    private func card(for id: UUID) -> Activity<OperationActivityAttributes>? {
        live[id] ?? Activity<OperationActivityAttributes>.activities.first {
            $0.attributes.operationID == id && $0.activityState == .active
        }
    }
    #endif

    func end(id: UUID, progressText: String, errorMessage: String?, canRetry: Bool = false) {
        offered.remove(id)
        armed.remove(id)
        #if os(iOS)
        guard let activity = live.removeValue(forKey: id) else { return }
        let state = OperationActivityAttributes.ContentState(progressText: progressText,
                                                             isFinished: true,
                                                             errorMessage: errorMessage,
                                                             canRetry: canRetry ? true : nil)
        let linger = errorMessage == nil ? Self.finishedLingerSeconds : Self.failedLingerSeconds
        let content = ActivityContent(state: state, staleDate: nil)
        let alert = Self.finishedAlert(title: activity.attributes.title, state: state)
        let policy = ActivityUIDismissalPolicy.after(Date().addingTimeInterval(linger))
        Task {
            await activity.update(content, alertConfiguration: alert)
            await activity.end(content, dismissalPolicy: policy)
        }
        #if DEBUG
        LiveActivityProbe.note("ended: \(progressText) error=\(errorMessage ?? "-")")
        #endif
        #endif
    }

    #if os(iOS)
    /// Opens the island wide with how the run ended
    static func finishedAlert(title: String,
                              state: OperationActivityAttributes.ContentState) -> AlertConfiguration {
        let headline = OperationPresentation.headline(state)
        return AlertConfiguration(title: LocalizedStringResource(stringLiteral: headline),
                                  body: LocalizedStringResource(stringLiteral: title),
                                  sound: .default)
    }
    #endif

    /// Ends cards no server job will ever close
    func endOrphans() {
        #if os(iOS)
        let followed = Self.followedJobs()
        Task {
            for activity in Activity<OperationActivityAttributes>.activities {
                guard !live.values.contains(where: { $0.id == activity.id }),
                      followed[activity.id] == nil else { continue }
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    /// Ends followed cards the server stopped moving
    func endUnclaimed() {
        #if os(iOS)
        var followed = Self.followedJobs()
        for activity in Activity<OperationActivityAttributes>.activities where !isOurs(activity) {
            guard followed[activity.id] != nil else { continue }
            let stale = activity.content.staleDate.map { $0 < Date() } ?? true
            guard stale || activity.activityState != .active else { continue }
            followed[activity.id] = nil
            Task { await activity.end(nil, dismissalPolicy: .default) }
        }
        Self.saveFollowedJobs(followed.filter { id, _ in
            Activity<OperationActivityAttributes>.activities.contains { $0.id == id }
        })
        #endif
    }

    /// Takes a finished card off the screen at once
    func dismissCard(of operation: UUID) {
        #if os(iOS)
        for activity in Activity<OperationActivityAttributes>.activities
        where activity.attributes.operationID == operation {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    /// The operation now showing the card opened for that id
    func operation(showingCardOf cardOperation: UUID) -> UUID? {
        #if os(iOS)
        return live.first { $0.value.attributes.operationID == cardOperation }?.key
        #else
        return nil
        #endif
    }

    // MARK: - Cards that follow a server job

    private static let followedKey = "operationActivities.followedJobs"

    /// Remembers which server job a card follows
    func remember(_ operation: UUID, followsJob jobID: String) {
        #if os(iOS)
        guard let activity = live[operation] else { return }
        var followed = Self.followedJobs()
        followed[activity.id] = jobID
        Self.saveFollowedJobs(followed)
        #endif
    }

    private static func followedJobs() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: followedKey) as? [String: String] ?? [:]
    }

    private static func saveFollowedJobs(_ followed: [String: String]) {
        UserDefaults.standard.set(followed, forKey: followedKey)
    }

    #if os(iOS)
    private func isOurs(_ activity: Activity<OperationActivityAttributes>) -> Bool {
        live.values.contains { $0.id == activity.id }
    }

    /// Takes over the card left for this job
    private func reclaim(_ jobID: String, for id: UUID) -> Bool {
        let followed = Self.followedJobs()
        guard let activity = Activity<OperationActivityAttributes>.activities.first(where: {
            followed[$0.id] == jobID && $0.activityState == .active && !isOurs($0)
        }) else { return false }
        live[id] = activity
        followPushToken(of: activity, for: id)
        return true
    }
    #endif
}
