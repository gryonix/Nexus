package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.AIDateGroup
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ai.AiWeekly
import com.skaymer.gryonixnexus.app.shell.AppModule
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AppTopBar
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import kotlinx.coroutines.launch

private enum class Page { LIST, CHAT, PROVIDER }

/** The AI section: chats, weekly summary and provider settings. */
@Composable
fun AiSection() {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val config by app.aiSettings.config.collectAsState()
    if (!config.agreed) {
        AiAgreement(onAgree = { app.aiSettings.update { it.copy(agreed = true) } },
            onCancel = { app.modules.set(AppModule.AI, false) })
        return
    }
    val chats = app.aiChats
    val openId by chats.openChatId.collectAsState()
    var page by remember { mutableStateOf(Page.LIST) }
    val shown = if (openId != null) Page.CHAT else page
    BackHandler(enabled = shown != Page.LIST) { chats.open(null); page = Page.LIST }
    when (shown) {
        Page.CHAT -> AiChatScreen(openId.orEmpty(), onBack = { chats.open(null) })
        Page.PROVIDER -> AiProviderPage(onBack = { page = Page.LIST })
        Page.LIST -> AiChatList(onProvider = { page = Page.PROVIDER })
    }
}

@Composable
private fun AiChatList(onProvider: () -> Unit) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val config by app.aiSettings.config.collectAsState()
    val history by app.aiChats.history.collectAsState()
    val scope = rememberCoroutineScope()
    var summarising by remember { mutableStateOf(false) }
    val newTitle = stringResource(R.string.ai_new_chat)
    Column(Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground)) {
        AppTopBar(stringResource(R.string.tab_ai))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = GroupedContentPadding, verticalArrangement = GroupedSpacing) {
            item {
                GroupedSection {
                    ValueRow(
                        title = if (config.isConfigured) "${config.providerId} · ${config.model}" else stringResource(R.string.ai_choose_provider),
                        value = null, onClick = onProvider,
                    )
                    ActionRow(stringResource(R.string.ai_weekly_summary), enabled = !summarising, onClick = {
                        summarising = true
                        scope.launch {
                            val context = AiWeekly.context(app)
                            summarising = false
                            app.aiChats.start(context)
                        }
                    })
                    ActionRow(newTitle, showDivider = false, onClick = { app.aiChats.open(app.aiChats.newChat(newTitle)) })
                }
            }
            history.groups(System.currentTimeMillis()).forEach { (group, chats) ->
                item(key = group.name) {
                    GroupedSection(header = stringResource(groupTitle(group))) {
                        chats.forEachIndexed { index, chat ->
                            GroupedRow(
                                onClick = { app.aiChats.open(chat.id) },
                                showDivider = index != chats.lastIndex,
                                trailing = {
                                    TextButton(onClick = { app.aiChats.delete(chat.id) }) {
                                        Text(stringResource(R.string.ai_delete))
                                    }
                                },
                            ) { Text(chat.title, maxLines = 1) }
                        }
                    }
                }
            }
        }
    }
}

private fun groupTitle(group: AIDateGroup): Int = when (group) {
    AIDateGroup.TODAY -> R.string.ai_today
    AIDateGroup.YESTERDAY -> R.string.ai_yesterday
    AIDateGroup.LAST_WEEK -> R.string.ai_prev7
    AIDateGroup.EARLIER -> R.string.ai_earlier
}
