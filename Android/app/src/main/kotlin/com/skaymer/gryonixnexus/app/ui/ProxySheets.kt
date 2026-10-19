package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.ProxyPasswords
import com.skaymer.gryonixnexus.app.servers.ProxyStore
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.ProxyProfile
import java.util.UUID

@Composable
fun ProxyListSheet(
    store: SettingsStore,
    secrets: SecretStore,
    onClose: () -> Unit,
) {
    var proxies by remember { mutableStateOf(ProxyStore.all(store)) }
    var editing by remember { mutableStateOf<ProxyProfile?>(null) }

    IOSSheet(
        title = stringResource(R.string.proxies),
        onClose = onClose,
        closeLabel = stringResource(R.string.group_cancel),
    ) {
        GroupedSection(note = stringResource(R.string.proxies_note)) {
            if (proxies.isEmpty()) {
                ValueRow(
                    title = stringResource(R.string.proxies_none),
                    value = null,
                    onClick = null,
                )
            }
            proxies.forEachIndexed { index, proxy ->
                ValueRow(
                    title = proxy.displayName,
                    subtitle = "${proxy.host}:${proxy.port}",
                    value = if (proxy.kind == ProxyProfile.Kind.SOCKS5) "SOCKS5" else "HTTP",
                    onClick = { editing = proxy },
                    showDivider = index != proxies.lastIndex,
                )
            }
            ActionRow(
                text = stringResource(R.string.proxies_add),
                showDivider = false,
                onClick = { editing = ProxyProfile(id = UUID.randomUUID().toString()) },
            )
        }
    }

    editing?.let { proxy ->
        ProxyEditorSheet(
            proxy = proxy,
            store = store,
            secrets = secrets,
            onClose = {
                editing = null
                proxies = ProxyStore.all(store)
            },
        )
    }
}

/** One proxy's own fields */
@Composable
private fun ProxyEditorSheet(
    proxy: ProxyProfile,
    store: SettingsStore,
    secrets: SecretStore,
    onClose: () -> Unit,
) {
    var draft by remember(proxy.id) { mutableStateOf(proxy) }
    var password by remember(proxy.id) { mutableStateOf("") }
    var passwordTouched by remember(proxy.id) { mutableStateOf(false) }
    var port by remember(proxy.id) { mutableStateOf(proxy.port.toString()) }
    val saved = remember(proxy.id) { ProxyStore.profile(store, proxy.id) != null }

    IOSSheet(
        title = stringResource(R.string.proxy),
        onClose = onClose,
        closeLabel = stringResource(R.string.group_cancel),
        action = SheetAction(
            title = stringResource(R.string.save),
            onSelect = {
                val finished = draft.copy(port = port.toIntOrNull() ?: 1080)
                val list = ProxyStore.all(store).toMutableList()
                val index = list.indexOfFirst { it.id == finished.id }
                if (index >= 0) list[index] = finished else list.add(finished)
                ProxyStore.save(store, list)
                if (passwordTouched) ProxyPasswords(secrets).setPassword(finished.id, password)
                onClose()
            },
        ),
    ) {
        GroupedSection(note = stringResource(R.string.proxy_kind_note)) {
            FieldRow(
                label = stringResource(R.string.proxy_name),
                value = draft.name,
                placeholder = "Office",
                onValueChange = { draft = draft.copy(name = it) },
            )
            ChoiceRow(
                title = stringResource(R.string.proxy_kind),
                value = if (draft.kind == ProxyProfile.Kind.SOCKS5) "SOCKS5" else "HTTP CONNECT",
                options = listOf(
                    "SOCKS5" to { draft = draft.copy(kind = ProxyProfile.Kind.SOCKS5) },
                    "HTTP CONNECT" to { draft = draft.copy(kind = ProxyProfile.Kind.HTTP_CONNECT) },
                ),
            )
            FieldRow(
                label = stringResource(R.string.host_label),
                value = draft.host,
                placeholder = "proxy.example.com",
                onValueChange = { draft = draft.copy(host = it) },
            )
            FieldRow(
                label = stringResource(R.string.port_label),
                value = port,
                onValueChange = { port = it.filter(Char::isDigit) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                showDivider = false,
            )
        }
        GroupedSection(footer = stringResource(R.string.proxy_signin_note)) {
            FieldRow(
                label = stringResource(R.string.user_label),
                value = draft.username,
                onValueChange = { draft = draft.copy(username = it) },
            )
            FieldRow(
                label = stringResource(R.string.password_label),
                value = password,
                onValueChange = {
                    password = it
                    passwordTouched = true
                },
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                showDivider = false,
            )
        }
        if (saved) {
            GroupedSection {
                ActionRow(
                    text = stringResource(R.string.files_delete),
                    danger = true,
                    showDivider = false,
                    onClick = {
                        ProxyStore.remove(store, secrets, proxy.id)
                        onClose()
                    },
                )
            }
        }
    }
}

@Composable
fun ProxyPickerSheet(
    selected: String?,
    store: SettingsStore,
    onSelect: (String?) -> Unit,
    onClose: () -> Unit,
) {
    val proxies = remember { ProxyStore.all(store) }
    IOSSheet(
        title = stringResource(R.string.proxy),
        onClose = onClose,
        closeLabel = stringResource(R.string.group_cancel),
    ) {
        GroupedSection(note = stringResource(R.string.proxy_pick_note)) {
            CheckRow(
                title = stringResource(R.string.server_bastion_none),
                checked = selected == null,
                onClick = { onSelect(null) },
                showDivider = proxies.isNotEmpty(),
            )
            proxies.forEachIndexed { index, proxy ->
                CheckRow(
                    title = proxy.displayName,
                    subtitle = "${proxy.host}:${proxy.port}",
                    checked = selected == proxy.id,
                    onClick = { onSelect(proxy.id) },
                    showDivider = index != proxies.lastIndex,
                )
            }
        }
    }
}
