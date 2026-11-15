import Foundation

public enum AppGroup {
    #if os(macOS)
    public static let identifier = "Z4PMRLY8L2.group.com.skaymer.gryonixnexus"
    #else
    public static let identifier = "group.com.skaymer.gryonixnexus"
    #endif

    /// Writable shared folder; tvOS allows only Caches
    public static func writableURL(_ groupIdentifier: String = identifier) -> URL? {
        guard let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }
        #if os(tvOS)
        return group.appendingPathComponent("Library/Caches", isDirectory: true)
        #else
        return group
        #endif
    }
}
