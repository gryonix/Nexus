package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.storage.StorageAgentTasks
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
import com.skaymer.gryonixnexus.app.install.InstallTarget
import com.skaymer.gryonixnexus.app.install.StorageChoice
import com.skaymer.gryonixnexus.app.install.StorageStep
import com.skaymer.gryonixnexus.app.storage.StorageState
import com.skaymer.gryonixnexus.app.storage.StorageViewModel
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** The server's own account and the default sign-in */
data class StorageAccount(val user: String, val sign: StorageSign, val viaAgent: Boolean = false) {
    companion object {
        fun of(server: Deployment, host: SSHHostID): StorageAccount {
            val user = server.nodes.firstOrNull { it.sshHost == host }?.endpoint?.user ?: server.entry.user
            val serverFirst = user == "root" || server.services.isEmpty() || server.usesAgent
            return StorageAccount(user, StorageSign(usesServer = serverFirst), viaAgent = server.usesAgent)
        }
    }
}

/** Server account, or root with an optional password */
data class StorageSign(val usesServer: Boolean, val user: String = "root", val password: String = "") {
    fun run(model: StorageViewModel, server: Deployment, host: SSHHostID, step: StorageStep) {
        if (usesServer) return model.runAsServer(server, host, step)
        val secret = if (password.isEmpty()) InstallTarget.Secret.AppKey else InstallTarget.Secret.Password(password)
        model.run(server, host, user, secret, step)
    }
}

@Composable
internal fun StorageSignInRows(account: StorageAccount, sign: StorageSign, onChange: (StorageSign) -> Unit) {
    ToggleRow(
        title = stringResource(R.string.storage_use_server_account, account.user),
        subtitle = stringResource(
            when {
                sign.usesServer && account.viaAgent -> R.string.storage_agent_note
                sign.usesServer -> R.string.storage_server_account_note
                else -> R.string.storage_root_note
            },
        ),
        checked = sign.usesServer,
        onCheckedChange = { onChange(sign.copy(usesServer = it)) },
        showDivider = !sign.usesServer,
    )
    if (sign.usesServer) return
    FieldRow(
        label = stringResource(R.string.install_account),
        value = sign.user,
        onValueChange = { onChange(sign.copy(user = it)) },
    )
    FieldRow(
        label = stringResource(R.string.install_auth_password),
        value = sign.password,
        onValueChange = { onChange(sign.copy(password = it)) },
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        showDivider = false,
    )
}

/** Builds a new array from free disks */
@Composable
internal fun StorageBuildSheet(
    model: StorageViewModel,
    state: StorageState,
    server: Deployment,
    host: SSHHostID,
    account: StorageAccount,
    onClose: () -> Unit,
) {
    val hardware = state.hardware ?: return
    var choice by remember { mutableStateOf(StorageChoice(buildsRaid = true)) }
    var sign by remember { mutableStateOf(account.sign) }
    val candidates = RaidPlan.candidates(hardware)
    val plan = RaidPlan.storage(choice.raidLevel, candidates.filter { it.path in choice.raidDisks }, hardware, choice.raidKind)
    val ready = plan.isValid && choice.confirmed && !state.running
    IOSSheet(
        title = stringResource(R.string.storage_build_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.access_cancel),
        action = SheetAction(
            title = stringResource(R.string.storage_build_title),
            enabled = ready,
            onSelect = {
                sign.run(model, server, host, StorageAgentTasks.raid(plan))
                onClose()
            },
        ),
    ) {
        GroupedSection(
            header = stringResource(R.string.storage_raid),
            footer = stringResource(R.string.storage_raid_mount_note, plan.mountPoint.orEmpty()),
        ) {
            RaidChoiceRows(choice, plan, candidates) { change -> choice = change(choice) }
        }
        GroupedSection(header = stringResource(R.string.storage_sign_in)) {
            StorageSignInRows(account, sign) { sign = it }
        }
    }
}
