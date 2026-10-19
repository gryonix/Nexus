package com.skaymer.gryonixnexus.app.session

import java.security.Security
import org.bouncycastle.jce.provider.BouncyCastleProvider

object SshjSecurity {
    @Volatile
    private var installed = false

    @Synchronized
    fun install() {
        if (installed) return
        Security.removeProvider(BouncyCastleProvider.PROVIDER_NAME)
        Security.insertProviderAt(BouncyCastleProvider(), 1)
        installed = true
    }
}
