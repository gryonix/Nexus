import AgentClient
import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

@available(macOS 15.0, *)
enum ServerMods {
    /// What one listing call brings back
    struct Files: Sendable {
        var files: [Gryonixnexusd_V1_ModFile] = []
        var freeBytes: UInt64 = 0
        var reachedServer = false
        var failure: String?

        init() {}

        init(_ list: Gryonixnexusd_V1_ModFileList) {
            files = list.files
            freeBytes = list.diskFreeBytes
            reachedServer = true
        }
    }

    struct SearchOutcome: Sendable {
        var projects: [Gryonixnexusd_V1_ModProject] = []
        var total: UInt32 = 0
        var filteredByVersion = false
        var failure: String?
    }

    private static func demoProjects(matching query: String) -> [Gryonixnexusd_V1_ModProject] {
        let rows: [(String, String, String, UInt64, String, String)] = [
            ("sodium", "Sodium", "A rendering engine replacement that improves frame rates.",
             48_300_000, "LGPL-3.0-only", "CaffeineMC"),
            ("fabric-api", "Fabric API", "The library nearly every Fabric mod depends on.",
             91_700_000, "Apache-2.0", "modmuss50"),
            ("journeymap", "JourneyMap", "A live map of where you have been, in game and in a browser.",
             12_100_000, "ARR", "techbrew"),
            ("simple-voice-chat", "Simple Voice Chat", "Proximity voice chat for the whole server.",
             34_500_000, "MIT", "henkelmax")
        ]
        let needle = query.lowercased()
        return rows.filter { needle.isEmpty || $0.1.lowercased().contains(needle) || $0.0.contains(needle) }
            .map { row in
                var project = Gryonixnexusd_V1_ModProject()
                project.slug = row.0
                project.title = row.1
                project.description_p = row.2
                project.downloads = row.3
                project.license = row.4
                project.author = row.5
                project.projectID = row.0
                project.projectType = "mod"
                return project
            }
    }

    private static func demoFiles() -> Files {
        var file = Gryonixnexusd_V1_ModFile()
        file.name = "worldedit-bukkit-7.3.0.jar"
        file.slot = .mods
        file.sizeBytes = 12_582_912
        file.modifiedUnix = 1_788_000_000
        var files = Files()
        files.files = [file]
        files.freeBytes = 42_949_672_960
        files.reachedServer = true
        return files
    }

    private static func message(for error: Error) -> String {
        if let agent = error as? AgentError, case .rpc(_, let text) = agent { return text }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func operations(_ deployment: Deployment) async throws -> (AgentModOperations, AgentConnection.Session) {
        let session = try await AgentConnection.open(deployment: deployment)
        return (AgentModOperations(client: session.client), session)
    }

    static func search(query: String,
                       gameVersion: String,
                       loader: String,
                       limit: UInt32 = 20,
                       deployment: Deployment) async -> SearchOutcome {
        guard deployment.usesAgent else { return SearchOutcome() }
        if DemoServer.isDemo(deployment) {
            let projects = demoProjects(matching: query)
            return SearchOutcome(projects: projects,
                                 total: UInt32(projects.count),
                                 filteredByVersion: !gameVersion.isEmpty,
                                 failure: nil)
        }
        var outcome = SearchOutcome()
        do {
            let (mods, session) = try await operations(deployment)
            defer { Task { await session.runner.disconnect() } }
            let result = try await mods.search(query: query,
                                               gameVersion: gameVersion,
                                               loader: loader,
                                               limit: limit)
            outcome.projects = result.projects
            outcome.total = result.total
            outcome.filteredByVersion = result.filteredByVersion
        } catch {
            outcome.failure = message(for: error)
        }
        return outcome
    }

    enum Pinned: Sendable {
        case entry(String)
        case refused(String)
    }

    static func pinnedEntry(for project: Gryonixnexusd_V1_ModProject,
                            gameVersion: String,
                            loader: String,
                            deployment: Deployment) async -> Pinned {
        guard deployment.usesAgent else {
            return .refused(UIL10n.string("This server is not managed by the gryonixNexus agent."))
        }
        if DemoServer.isDemo(deployment) {
            let slug = project.slug.isEmpty ? project.projectID : project.slug
            return .entry(AgentModOperations.entry(slug: slug, versionID: "AANobbMO"))
        }
        do {
            let (mods, session) = try await operations(deployment)
            defer { Task { await session.runner.disconnect() } }
            let versions = try await mods.versions(project: project.slug.isEmpty ? project.projectID : project.slug,
                                                   gameVersion: gameVersion,
                                                   loader: loader)
            guard let pick = versions.first(where: { $0.versionType == "release" }) ?? versions.first else {
                return .refused(UIL10n.string("%@ has no build for this server's version.", project.title))
            }
            let slug = project.slug.isEmpty ? project.projectID : project.slug
            return .entry(AgentModOperations.entry(slug: slug, versionID: pick.versionID))
        } catch {
            return .refused(message(for: error))
        }
    }

    static func files(deployment: Deployment) async -> Files {
        guard deployment.usesAgent else { return Files() }
        if DemoServer.isDemo(deployment) { return demoFiles() }
        var result = Files()
        do {
            let (mods, session) = try await operations(deployment)
            defer { Task { await session.runner.disconnect() } }
            result = Files(try await mods.files())
        } catch {
            result.failure = message(for: error)
        }
        return result
    }

    static func upload(name: String,
                       slot: Gryonixnexusd_V1_ModSlot,
                       content: Data,
                       deployment: Deployment) async -> Files {
        guard deployment.usesAgent else { return Files() }
        if DemoServer.isDemo(deployment) {
            var files = demoFiles()
            var added = Gryonixnexusd_V1_ModFile()
            added.name = name
            added.slot = slot
            added.sizeBytes = UInt64(content.count)
            added.modifiedUnix = Int64(Date().timeIntervalSince1970)
            files.files.append(added)
            return files
        }
        var result = Files()
        do {
            let (mods, session) = try await operations(deployment)
            defer { Task { await session.runner.disconnect() } }
            result = Files(try await mods.upload(name: name, slot: slot, content: content))
        } catch {
            result.failure = message(for: error)
        }
        return result
    }

    static func delete(name: String,
                       slot: Gryonixnexusd_V1_ModSlot,
                       deployment: Deployment) async -> Files {
        guard deployment.usesAgent else { return Files() }
        if DemoServer.isDemo(deployment) {
            var files = demoFiles()
            files.files.removeAll { $0.name == name }
            return files
        }
        var result = Files()
        do {
            let (mods, session) = try await operations(deployment)
            defer { Task { await session.runner.disconnect() } }
            result = Files(try await mods.delete(name: name, slot: slot))
        } catch {
            result.failure = message(for: error)
        }
        return result
    }
}
