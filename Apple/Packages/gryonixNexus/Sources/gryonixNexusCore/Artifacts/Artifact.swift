import Foundation

/// A single generated file + metadata for manual application
public extension Artifact {
    /// The script that reports and hands the server over
    static let finishSetupName = "finish-setup.sh"
}

public struct Artifact: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let fileName: String
    public let suggestedPath: String?
    public let kind: ArtifactKind
    public let contents: String
    public let summary: String             // human-readable purpose
    public let server: ServerRole?

    public init(
        fileName: String,
        suggestedPath: String? = nil,
        kind: ArtifactKind,
        contents: String,
        summary: String,
        server: ServerRole? = nil
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.suggestedPath = suggestedPath
        self.kind = kind
        self.contents = contents
        self.summary = summary
        self.server = server
    }
}
