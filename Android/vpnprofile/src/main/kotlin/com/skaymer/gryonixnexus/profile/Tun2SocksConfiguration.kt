package com.skaymer.gryonixnexus.profile

object Tun2SocksConfiguration {
    const val ADDRESS = "198.18.0.1"

    /** `/30`, as a prefix length: what `VpnService.Builder.addAddress` takes */
    const val PREFIX_LENGTH = 30

    /** Large on purpose */
    const val MTU = 8500

    /** Small per-connection memory, as hev advises for low-memory systems */
    const val TCP_BUFFER_BYTES = 4096
    const val TASK_STACK_BYTES = 20480 + TCP_BUFFER_BYTES

    /** A silent UDP flow closes after ten seconds */
    const val UDP_IDLE_MILLISECONDS = 10_000

    /** Past this, the least recently used session closes */
    const val MAX_SESSIONS = 128

    fun yaml(
        access: LocalProxyAccess,
        address: String = ADDRESS,
        mtu: Int = MTU,
    ): String = """
        tunnel:
          mtu: $mtu
          ipv4: $address
        socks5:
          port: ${access.port}
          address: 127.0.0.1
          username: ${access.username}
          password: ${access.password}
          udp: 'udp'
        misc:
          task-stack-size: $TASK_STACK_BYTES
          tcp-buffer-size: $TCP_BUFFER_BYTES
          udp-read-write-timeout: $UDP_IDLE_MILLISECONDS
          max-session-count: $MAX_SESSIONS
          log-level: warn
    """.trimIndent()
}
