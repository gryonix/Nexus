package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.AIContext
import com.skaymer.gryonixnexus.aiassistant.AIContextKind
import com.skaymer.gryonixnexus.aiassistant.AIContextSection
import com.skaymer.gryonixnexus.aiassistant.AIPrompts
import com.skaymer.gryonixnexus.app.ui.design.AppTopBar
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton

@Composable
private fun Notice(title: String, body: String, action: String, onAction: () -> Unit, onCancel: (() -> Unit)?, extra: @Composable () -> Unit = {}) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(title, style = MaterialTheme.typography.headlineSmall)
        Text(body)
        extra()
        ProminentButton(action, onAction)
        if (onCancel != null) PlainButton(stringResource(R.string.ai_cancel), onCancel)
    }
}

/** Shown once when the module is first turned on. */
@Composable
fun AiAgreement(onAgree: () -> Unit, onCancel: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        AppTopBar(stringResource(R.string.tab_ai))
        Notice(stringResource(R.string.ai_can_be_wrong), stringResource(R.string.ai_agreement_body),
            stringResource(R.string.ai_agree), onAgree, onCancel)
    }
}

/** Lists what a cloud provider receives, with a redacted example. */
@Composable
fun AiCloudNotice(providerName: String, onAgree: () -> Unit, onCancel: () -> Unit) {
    var example by remember { mutableStateOf(false) }
    Notice(stringResource(R.string.ai_sent_to, providerName), stringResource(R.string.ai_cloud_body, providerName),
        stringResource(R.string.ai_agree), onAgree, onCancel) {
        PlainButton(stringResource(R.string.ai_show_example), { example = !example })
        if (example) Text(cloudExample(), fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun AiLocalNotice(onAgree: () -> Unit) {
    Notice(stringResource(R.string.ai_data_home), stringResource(R.string.ai_local_body), stringResource(R.string.ai_ok), onAgree, null)
}

internal fun cloudExample(): String = AIPrompts.contextMessage(
    AIContext(
        AIContextKind.SERVICE, "web",
        listOf(AIContextSection("Logs", "starting web\nDB_PASSWORD=hunter2hunter2\nAuthorization: Bearer abc123def456\nerror: connection refused")),
    ),
)
