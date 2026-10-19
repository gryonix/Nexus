public struct UninstallSpec: Sendable, Hashable {
    public let composeProject: String?
    /// Directory holding compose/config files
    public let configDirectory: String?
    public let dataPaths: [String]
    public let backupDirs: [String]
    /// Bash run before the compose project goes down (e.g
    public let preSteps: [String]
    public let postSteps: [String]

    public init(composeProject: String? = nil, configDirectory: String? = nil,
                dataPaths: [String] = [], backupDirs: [String] = [],
                preSteps: [String] = [], postSteps: [String] = []) {
        self.composeProject = composeProject
        self.configDirectory = configDirectory
        self.dataPaths = dataPaths
        self.backupDirs = backupDirs
        self.preSteps = preSteps
        self.postSteps = postSteps
    }
}
