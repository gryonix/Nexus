import Foundation
import VPNProfile
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
enum ProfileInstaller {
    enum InstallError: LocalizedError {
        case couldNotOpen

        var errorDescription: String? {
            switch self {
            case .couldNotOpen:
                return UIL10n.string("Could not open the profile for installing.")
            }
        }
    }

    enum NextStep {
        /// iOS: the browser has the profile; Settings finishes the job
        case openSettings
        /// macOS: the install prompt is already on screen
        case confirmInThePrompt
    }

    @discardableResult
    static func install(_ profile: Data, fileName: String) async throws -> NextStep {
        #if os(macOS)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent(LocalProfileServer.safe(fileName))
        try profile.write(to: url, options: .atomic)
        guard NSWorkspace.shared.open(url) else {
            try? FileManager.default.removeItem(at: folder)
            throw InstallError.couldNotOpen
        }
        Task.detached {
            try? await Task.sleep(for: .seconds(600))
            try? FileManager.default.removeItem(at: folder)
        }
        return .confirmInThePrompt
        #else
        let server = LocalProfileServer(profile: profile, fileName: fileName)
        let port = try await server.start()
        guard let url = URL(string: "http://127.0.0.1:\(port)\(server.path)") else {
            await server.stop()
            throw InstallError.couldNotOpen
        }
        guard await UIApplication.shared.open(url) else {
            await server.stop()
            throw InstallError.couldNotOpen
        }
        return .openSettings
        #endif
    }
}
