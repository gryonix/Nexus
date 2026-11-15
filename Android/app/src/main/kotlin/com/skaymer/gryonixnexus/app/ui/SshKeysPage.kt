package com.skaymer.gryonixnexus.app.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.secrets.UserSshKeyStore
import com.skaymer.gryonixnexus.app.security.LocalDeviceGate
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.SshKeyKind
import com.skaymer.gryonixnexus.servercontrol.UserSshKey
import com.skaymer.gryonixnexus.transport.UserSshKeyGenerator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Settings, Security, SSH keys */
@Composable
fun SshKeysPage(store: UserSshKeyStore) {
    val keys by store.keys.collectAsState()
    var openID by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val open = keys.firstOrNull { it.id == openID }
    if (open != null) {
        SshKeyDetail(open, store) { openID = null }
        return
    }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { KeyList(keys) { openID = it } }
        item {
            GroupedSection(footer = stringResource(R.string.ssh_keys_footer)) {
                SshKeyKind.entries.forEach { kind ->
                    ActionRow(
                        text = stringResource(R.string.ssh_keys_generate, kind.displayName),
                        enabled = !busy,
                        showDivider = kind != SshKeyKind.entries.last(),
                        onClick = {
                            scope.launch {
                                busy = true
                                val name = nextName(kind, keys.map { it.name })
                                store.add(withContext(Dispatchers.Default) { UserSshKeyGenerator.generate(kind, name) })
                                busy = false
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun KeyList(keys: List<UserSshKey>, onOpen: (String) -> Unit) {
    GroupedSection {
        if (keys.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(stringResource(R.string.ssh_keys_empty), color = Gryonix.colors.secondaryLabel)
            }
        }
        keys.forEach { key ->
            GroupedRow(
                showDivider = key != keys.last(),
                onClick = { onOpen(key.id) },
                trailing = { DisclosureChevron() },
            ) { RowLabel(key.name, "${key.kind.displayName}  ${key.fingerprint}") }
        }
    }
}

/** Default names for new keys */
internal fun nextName(kind: SshKeyKind, existing: List<String>): String {
    val base = kind.displayName
    if (base !in existing) return base
    var number = 2
    while ("$base $number" in existing) number++
    return "$base $number"
}

@Composable
private fun SshKeyDetail(key: UserSshKey, store: UserSshKeyStore, onClose: () -> Unit) {
    val context = LocalContext.current
    val gate = LocalDeviceGate.current
    val scope = rememberCoroutineScope()
    val copy = rememberSecretClipboard()
    val exportReason = stringResource(R.string.ssh_keys_export_reason)
    var installing by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    androidx.activity.compose.BackHandler(onBack = onClose)
    if (installing) {
        SshKeyInstallPage(key) { installing = false }
        return
    }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection {
                PendingTextRow(
                    label = stringResource(R.string.name_label),
                    saved = key.name,
                    onApply = { store.rename(key.id, it.trim()) },
                )
            }
        }
        item { PublicKeyBlock(key) }
        item {
            GroupedSection {
                ActionRow(stringResource(R.string.ssh_keys_copy_public), { copy(key.publicKey) })
                ActionRow(stringResource(R.string.ssh_keys_share_public), { shareText(context, key.publicKey) })
                ActionRow(stringResource(R.string.ssh_keys_install), { installing = true })
                ActionRow(stringResource(R.string.ssh_keys_export_private), {
                    scope.launch { if (gate.confirm(exportReason)) shareText(context, key.privateKeyPem) }
                })
                ActionRow(stringResource(R.string.ssh_keys_delete), { deleting = true }, danger = true, showDivider = false)
            }
        }
    }
    if (deleting) {
        com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert(
            title = stringResource(R.string.ssh_keys_delete_title),
            message = stringResource(R.string.ssh_keys_delete_hint),
            confirm = stringResource(R.string.ssh_keys_delete),
            destructive = true,
            onConfirm = { store.delete(key.id); deleting = false; onClose() },
            onCancel = { deleting = false },
        )
    }
}

@Composable
private fun PublicKeyBlock(key: UserSshKey) {
    val mono = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace)
    GroupedSection(header = key.name) {
        GroupedRow(showDivider = true) { Text(key.publicKey, style = mono, color = Gryonix.colors.label) }
        GroupedRow(showDivider = true) { Text(key.fingerprint, style = mono, color = Gryonix.colors.label) }
        GroupedRow(showDivider = false) {
            Text(key.randomArt, style = mono.copy(fontSize = 12.sp), color = Gryonix.colors.label,
                modifier = Modifier.padding(vertical = 4.dp))
        }
    }
}

internal fun shareText(context: Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** The app-wide key list */
@Composable
fun rememberUserSshKeyStore(): UserSshKeyStore {
    val app = LocalContext.current.applicationContext as GryonixApplication
    return remember { UserSshKeyStore(app.secrets) }
}
