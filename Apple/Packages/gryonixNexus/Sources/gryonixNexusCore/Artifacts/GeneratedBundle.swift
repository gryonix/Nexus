/// Result of running a recipe: files + warnings + notes.
public struct GeneratedBundle: Sendable {
    public let artifacts: [Artifact]
    public let warnings: [String]          // e.g. "check that port 25 isn't blocked by the provider"
    public let notes: [String]             // application order, manual steps
    /// Per-service scripts, then one that finishes
    public let serviceScripts: [Artifact]

    public init(artifacts: [Artifact], warnings: [String] = [], notes: [String] = [],
                serviceScripts: [Artifact] = []) {
        self.artifacts = artifacts
        self.warnings = warnings
        self.notes = notes
        self.serviceScripts = serviceScripts
    }
}
