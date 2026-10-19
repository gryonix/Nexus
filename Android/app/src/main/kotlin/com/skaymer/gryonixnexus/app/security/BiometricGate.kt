package com.skaymer.gryonixnexus.app.security

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import java.util.UUID
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

class BiometricGate(private val context: Context) : DeviceGate {
    override suspend fun confirm(reason: String): Boolean {
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        if (keyguard?.isDeviceSecure != true) return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) prompt(reason) else credentialScreen(keyguard, reason)
    }

    private suspend fun prompt(reason: String): Boolean = suspendCancellableCoroutine { continuation ->
        val cancellation = CancellationSignal()
        continuation.invokeOnCancellation { cancellation.cancel() }
        BiometricPrompt.Builder(context)
            .setTitle(reason)
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
            .build()
            .authenticate(
                cancellation,
                context.mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        if (continuation.isActive) continuation.resume(true)
                    }

                    override fun onAuthenticationError(code: Int, message: CharSequence) {
                        if (continuation.isActive) continuation.resume(false)
                    }
                },
            )
    }

    /** The system's own unlock screen, for Android 8–10 */
    private suspend fun credentialScreen(keyguard: KeyguardManager, reason: String): Boolean {
        val activity = context as? ComponentActivity ?: return false
        @Suppress("DEPRECATION")
        val intent = keyguard.createConfirmDeviceCredentialIntent(reason, null) ?: return false
        return suspendCancellableCoroutine { continuation ->
            lateinit var launcher: ActivityResultLauncher<Intent>
            launcher = activity.activityResultRegistry.register(
                "device-gate-${UUID.randomUUID()}",
                ActivityResultContracts.StartActivityForResult(),
            ) { result ->
                launcher.unregister()
                if (continuation.isActive) continuation.resume(result.resultCode == Activity.RESULT_OK)
            }
            continuation.invokeOnCancellation { launcher.unregister() }
            launcher.launch(intent)
        }
    }
}
