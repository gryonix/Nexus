import Foundation

public enum Tun2SocksConfiguration {
    public static let address = "198.18.0.1"
    public static let netmask = "255.255.255.252"
    /// IPv6 is routed in and carried like IPv4
    public static let address6 = "fd53:7978:7261::1"

    /// Large on purpose
    public static let mtu = 8500

    /// Small per-connection memory, as hev advises for iOS
    public static let tcpBufferBytes = 4096
    public static let taskStackBytes = 20480 + tcpBufferBytes
    /// A silent UDP flow closes after ten seconds
    public static let udpIdleMilliseconds = 10_000
    /// Past this, the least recently used session closes
    public static let maxSessions = 128

    public static func yaml(access: LocalProxyAccess,
                            address: String = Tun2SocksConfiguration.address,
                            mtu: Int = Tun2SocksConfiguration.mtu) -> String {
        """
        tunnel:
          mtu: \(mtu)
          ipv4: \(address)
          ipv6: '\(Tun2SocksConfiguration.address6)'
        socks5:
          port: \(access.port)
          address: 127.0.0.1
          username: \(access.username)
          password: \(access.password)
          udp: 'udp'
        misc:
          task-stack-size: \(taskStackBytes)
          tcp-buffer-size: \(tcpBufferBytes)
          udp-read-write-timeout: \(udpIdleMilliseconds)
          max-session-count: \(maxSessions)
          log-level: warn
        """
    }
}
