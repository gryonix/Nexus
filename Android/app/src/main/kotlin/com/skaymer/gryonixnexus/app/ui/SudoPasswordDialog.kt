package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.access.SudoProblem
import com.skaymer.gryonixnexus.app.access.SudoPrompter
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert

/** Asks a non-root account's password once, for any caller */
@Composable
fun SudoPasswordDialog(prompter: SudoPrompter) {
    val question by prompter.question.collectAsState()
    val current = question ?: return
    var password by remember(current) { mutableStateOf("") }
    IOSAlert(
        title = stringResource(R.string.sudo_title),
        message = listOfNotNull(
            stringResource(R.string.sudo_needed, current.username),
            sudoProblemText(current.problem),
        ).joinToString("\n\n"),
        onDismiss = { prompter.answer(null) },
        actions = listOf(
            AlertAction(stringResource(R.string.containers_cancel), onSelect = { prompter.answer(null) }),
            AlertAction(
                stringResource(R.string.sudo_allow),
                preferred = true,
                enabled = password.isNotEmpty(),
                onSelect = { prompter.answer(password) },
            ),
        ),
    ) {
        AlertFields {
            SudoPasswordField(password) { password = it }
        }
    }
}

@Composable
fun SudoPasswordField(value: String, onValueChange: (String) -> Unit) {
    FieldRow(
        label = stringResource(R.string.sudo_account_password),
        value = value,
        onValueChange = onValueChange,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        showDivider = false,
    )
}

@Composable
fun sudoProblemText(problem: SudoProblem?): String? = when (problem) {
    null -> null
    SudoProblem.WrongPassword -> stringResource(R.string.sudo_wrong_password)
    is SudoProblem.Failed -> stringResource(R.string.sudo_failed, problem.detail)
}
