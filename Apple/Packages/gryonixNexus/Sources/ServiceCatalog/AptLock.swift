public enum Apt {
    public static let lockWait = "-o DPkg::Lock::Timeout=600"

    /// Keeps edited config files instead of prompting
    public static let keepConfigs = "-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

    public static let options = "\(lockWait) \(keepConfigs)"

    public static let quiet = "DEBIAN_FRONTEND=noninteractive apt-get \(options)"

    /// Caddy's apt repository signs with an expired subkey
    public static let retiredSources = [
        "/etc/apt/sources.list.d/caddy-stable.list",
        "/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    ]

    /// Drops sources that would fail every apt-get update
    public static let dropRetiredSources = "rm -f " + retiredSources.joined(separator: " ")
}
