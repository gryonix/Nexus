package com.skaymer.gryonixnexus.app.vpn

object Tun2Socks {
    init {
        System.loadLibrary("hev-socks5-tunnel")
    }

    /** Runs the stack until [TProxyStopService] */
    external fun TProxyStartService(configPath: String, fd: Int)

    external fun TProxyStopService()

    /** `[txPackets, txBytes, rxPackets, rxBytes]`, as lwIP counted them */
    external fun TProxyGetStats(): LongArray
}
