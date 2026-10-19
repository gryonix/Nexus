package com.skaymer.gryonixnexus.app.ui

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Lan
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.security.BiometricGate
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import kotlinx.coroutines.launch

/** Where a system permission stands. */
enum class PermissionState { NOT_ASKED, ASKING, GRANTED, DENIED }

private const val SHOWN_KEY = "onboarding.permissionsShown"
private const val BIOMETRICS_KEY = "onboarding.biometricsGranted"
private const val LOCAL_NETWORK = "android.permission.ACCESS_LOCAL_NETWORK"
private const val LOCAL_NETWORK_SDK = 37

/** Shows the permissions screen once, on first launch. */
@Composable
fun PermissionsOnboardingGate(store: SettingsStore, content: @Composable () -> Unit) {
    var shown by remember { mutableStateOf(store.boolean(SHOWN_KEY) == true) }
    Box(Modifier.fillMaxSize()) {
        content()
        if (!shown) {
            PermissionsOnboarding(store) {
                store.setBoolean(SHOWN_KEY, true)
                shown = true
            }
        }
    }
}

@Composable
private fun PermissionsOnboarding(store: SettingsStore, onFinish: () -> Unit) {
    val context = LocalContext.current
    var network by remember { mutableStateOf(localNetworkState(context)) }
    var biometrics by remember { mutableStateOf(biometricState(context, store)) }
    Column(
        Modifier.fillMaxSize()
            .background(Gryonix.colors.groupedBackground)
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        OnboardingHeader()
        Column(Modifier.widthIn(max = 520.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (network != null) LocalNetworkRow(network!!) { network = it }
            if (biometrics != null) BiometricsRow(store, biometrics!!) { biometrics = it }
        }
        val allDone = network in listOf(null, PermissionState.GRANTED) &&
            biometrics in listOf(null, PermissionState.GRANTED)
        OnboardingFooter(allDone, onFinish)
    }
}

@Composable
private fun OnboardingHeader() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(
            Modifier.size(88.dp).background(Gryonix.colors.accent, RoundedCornerShape(24.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.VerifiedUser, null, tint = Color.White, modifier = Modifier.size(44.dp))
        }
        Text(
            stringResource(R.string.onboarding_title),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = Gryonix.colors.label,
            textAlign = TextAlign.Center,
        )
        Text(
            stringResource(R.string.onboarding_subtitle),
            color = Gryonix.colors.secondaryLabel,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun LocalNetworkRow(state: PermissionState, onChange: (PermissionState) -> Unit) {
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        onChange(if (it) PermissionState.GRANTED else PermissionState.DENIED)
    }
    PermissionRow(
        icon = Icons.Filled.Lan,
        tint = Color(0xFF0A84FF),
        title = stringResource(R.string.permission_local_network),
        detail = stringResource(R.string.permission_local_network_detail),
        state = state,
    ) {
        onChange(PermissionState.ASKING)
        launcher.launch(LOCAL_NETWORK)
    }
}

@Composable
private fun BiometricsRow(store: SettingsStore, state: PermissionState, onChange: (PermissionState) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val reason = stringResource(R.string.permission_biometrics_detail)
    PermissionRow(
        icon = Icons.Filled.Fingerprint,
        tint = Color(0xFF30D158),
        title = stringResource(R.string.permission_biometrics),
        detail = reason,
        state = state,
    ) {
        onChange(PermissionState.ASKING)
        scope.launch {
            val granted = BiometricGate(context).confirm(reason)
            store.setBoolean(BIOMETRICS_KEY, granted)
            onChange(if (granted) PermissionState.GRANTED else PermissionState.DENIED)
        }
    }
}

@Composable
private fun PermissionRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    detail: String,
    state: PermissionState,
    onAsk: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .background(Gryonix.colors.cardBackground, RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(44.dp).background(tint, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White)
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold, color = Gryonix.colors.label)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.secondaryLabel)
        }
        PermissionControl(state, onAsk)
    }
}

@Composable
private fun PermissionControl(state: PermissionState, onAsk: () -> Unit) {
    val context = LocalContext.current
    when (state) {
        PermissionState.NOT_ASKED -> OutlinedButton(onClick = onAsk, shape = CircleShape) {
            Text(stringResource(R.string.permission_allow))
        }
        PermissionState.ASKING -> CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
        PermissionState.GRANTED -> Icon(
            Icons.Filled.CheckCircle,
            stringResource(R.string.permission_allowed),
            tint = Color(0xFF30D158),
            modifier = Modifier.size(28.dp),
        )
        PermissionState.DENIED -> OutlinedButton(onClick = { openAppSettings(context) }, shape = CircleShape) {
            Text(stringResource(R.string.permission_open_settings))
        }
    }
}

@Composable
private fun OnboardingFooter(allDone: Boolean, onFinish: () -> Unit) {
    Column(
        Modifier.widthIn(max = 520.dp).fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Button(onClick = onFinish, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.onboarding_continue), modifier = Modifier.padding(vertical = 6.dp))
        }
        if (!allDone) {
            Spacer(Modifier.size(4.dp))
            TextButton(onClick = onFinish) {
                Text(stringResource(R.string.onboarding_not_now), color = Gryonix.colors.secondaryLabel)
            }
        }
    }
}

/** Null when there is no local network permission. */
private fun localNetworkState(context: Context): PermissionState? {
    if (Build.VERSION.SDK_INT < LOCAL_NETWORK_SDK) return null
    val granted = context.checkSelfPermission(LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED
    return if (granted) PermissionState.GRANTED else PermissionState.NOT_ASKED
}

/** Null when the device has no biometrics to set up. */
private fun biometricState(context: Context, store: SettingsStore): PermissionState? {
    if (!hasBiometrics(context)) return null
    if (store.boolean(BIOMETRICS_KEY) == true) return PermissionState.GRANTED
    return PermissionState.NOT_ASKED
}

private fun hasBiometrics(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
    val manager = context.getSystemService(BiometricManager::class.java) ?: return false
    return manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
        BiometricManager.BIOMETRIC_SUCCESS
}

private fun openAppSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
