package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.AIContext
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.shell.AppModule

/** The "Explain" button, shown only while the module is on. */
@Composable
fun AiExplainButton(context: () -> AIContext, modifier: androidx.compose.ui.Modifier = androidx.compose.ui.Modifier, after: () -> Unit = {}) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val on by app.modules.on.collectAsState()
    if (AppModule.AI !in on) return
    TextButton(modifier = modifier, onClick = { app.aiChats.start(context()); after() }) {
        Text(stringResource(R.string.ai_explain))
    }
}

@Composable
fun AiExplainFailure(title: String, error: String?, log: String) {
    if (error == null) return
    RefusalAdvice(error)
    AiExplainButton(context = { com.skaymer.gryonixnexus.app.ai.AiExplain.operation(title, error, log) })
}
