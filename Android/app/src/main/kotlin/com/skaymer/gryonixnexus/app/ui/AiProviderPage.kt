package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.AIProviderConfig
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.AppTopBar
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.catalog.LLMProvider
import com.skaymer.gryonixnexus.catalog.ServiceID

@Composable
fun AiProviderPage(onBack: () -> Unit) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val settings = app.aiSettings
    val config by settings.config.collectAsState()
    val servers by app.fleet.deployments.collectAsState()
    var key by remember(config.providerId) { mutableStateOf(settings.apiKey(config.providerId)) }
    var pending by remember { mutableStateOf<String?>(null) }
    pending?.let { id ->
        if (id == AIProviderConfig.OLLAMA_ID) {
            AiLocalNotice { settings.markLocalNoticeSeen(); pending = null }
        } else {
            AiCloudNotice(LLMProvider.ALL.firstOrNull { it.id == id }?.displayName ?: id,
                onAgree = { settings.markCloudNoticeSeen(id); pending = null },
                onCancel = { settings.update { it.copy(providerId = "") }; pending = null })
        }
        return
    }
    Column(Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground)) {
        AppTopBar(stringResource(R.string.ai_provider), onBack = onBack)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = GroupedContentPadding, verticalArrangement = GroupedSpacing) {
            item {
                GroupedSection(footer = stringResource(R.string.ai_advisor_only)) {
                    val choices = listOf("" to stringResource(R.string.ai_none)) +
                        LLMProvider.ALL.map { it.id to it.displayName } +
                        (AIProviderConfig.OLLAMA_ID to stringResource(R.string.ai_ollama_mine))
                    choices.forEachIndexed { index, (id, name) ->
                        CheckRow(name, config.providerId == id, showDivider = index != choices.lastIndex, onClick = {
                            settings.update { it.copy(providerId = id, model = AIProviderConfig.suggestedModel(id)) }
                            key = settings.apiKey(id)
                            val seen = if (id == AIProviderConfig.OLLAMA_ID) settings.hasSeenLocalNotice else settings.hasSeenCloudNotice(id)
                            if (id.isNotEmpty() && !seen) pending = id
                        })
                    }
                }
            }
            if (config.isLocal) {
                item { OllamaSection(config, servers.filter { ServiceID.OLLAMA in it.services }.map { it.id to it.name }) { c -> settings.update { c(it) } } }
            } else if (config.providerId.isNotEmpty()) {
                item {
                    GroupedSection(footer = stringResource(R.string.ai_key_stays)) {
                        FieldRow(stringResource(R.string.ai_model), config.model, { v -> settings.update { it.copy(model = v) } })
                        FieldRow(stringResource(R.string.ai_api_key), key, { key = it; settings.setApiKey(config.providerId, it) },
                            visualTransformation = PasswordVisualTransformation(), showDivider = false)
                    }
                }
                item {
                    GroupedSection(footer = stringResource(R.string.ai_zero_no_limit)) {
                        StepperRow(stringResource(R.string.ai_monthly_limit, if (config.monthlyLimit == 0) "–" else config.monthlyLimit.toString()),
                            config.monthlyLimit / 50_000, 0..1000, { v -> settings.update { it.copy(monthlyLimit = v * 50_000) } },
                            format = { "" })
                        Text(stringResource(R.string.ai_used_month, config.usedThisMonth.toString()), color = Gryonix.colors.secondaryLabel)
                    }
                }
            }
        }
    }
}

@Composable
private fun OllamaSection(config: com.skaymer.gryonixnexus.app.ai.AiConfig, servers: List<Pair<String, String>>, edit: ((com.skaymer.gryonixnexus.app.ai.AiConfig) -> com.skaymer.gryonixnexus.app.ai.AiConfig) -> Unit) {
    GroupedSection(footer = stringResource(R.string.ai_data_home)) {
        CheckRow(stringResource(R.string.ai_address_below), config.ollamaServerId.isEmpty(), onClick = { edit { it.copy(ollamaServerId = "") } })
        servers.forEach { (id, name) -> CheckRow(name, config.ollamaServerId == id, onClick = { edit { it.copy(ollamaServerId = id) } }) }
        if (config.ollamaServerId.isEmpty()) {
            FieldRow(stringResource(R.string.ai_ollama_address), config.ollamaUrl, { v -> edit { it.copy(ollamaUrl = v) } },
                placeholder = "https://ollama.example.net")
        }
        FieldRow(stringResource(R.string.ai_model), config.model, { v -> edit { it.copy(model = v) } }, showDivider = false)
    }
}
