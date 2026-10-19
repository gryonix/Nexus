import Foundation

/// Lets screenshots and UI tests stage an outdated demo agent
enum DemoAgentOffer {
    private static var mode: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_AGENT_OFFER"]
        #else
        nil
        #endif
    }

    static var installedVersion: String {
        mode == "bundled" ? "0.0.120" : AgentBootstrapOperations.shippedVersion
    }

    static var publishedVersion: String? {
        mode == "published" ? "999.0.0" : nil
    }
}
