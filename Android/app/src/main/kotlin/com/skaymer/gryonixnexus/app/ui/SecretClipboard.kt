package com.skaymer.gryonixnexus.app.ui

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt

@Composable
fun rememberSecretClipboard(): (String) -> Unit {
    val context = LocalContext.current
    return remember(context) { { text -> if (LicensePrompt.allow()) copySecret(context, text) } }
}

internal fun copySecret(context: Context, text: String) {
    val clip = ClipData.newPlainText("", text)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        clip.description.extras = PersistableBundle().apply {
            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        }
    }
    context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(clip)
}
