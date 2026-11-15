package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Pull down to start every load again */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PullToRefresh(onRefresh: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            refreshing = true
            onRefresh()
            scope.launch {
                delay(SPINNER_MS)
                refreshing = false
            }
        },
        modifier = modifier.fillMaxSize(),
    ) { content() }
}

private const val SPINNER_MS = 900L
