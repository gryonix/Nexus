/// Artifact type — affects application hints and UI highlighting.
public enum ArtifactKind: Sendable, Hashable, CaseIterable {
    case serverConfig     // e.g. main.cf
    case dnsRecord        // MX/SPF/DKIM/DMARC
    case shellScript      // install/apply commands
    case keyMaterial
    case firewallRules
}
