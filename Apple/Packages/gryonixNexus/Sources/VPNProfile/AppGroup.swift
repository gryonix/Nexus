import Foundation

public enum AppGroup {
    #if os(macOS)
    public static let identifier = "Z4PMRLY8L2.group.com.skaymer.gryonixnexus"
    #else
    public static let identifier = "group.com.skaymer.gryonixnexus"
    #endif
}
