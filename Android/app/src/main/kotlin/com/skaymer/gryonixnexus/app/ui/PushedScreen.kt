package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

class PushedScreen {
    var title by mutableStateOf<String?>(null)
        private set
    var onBack by mutableStateOf<(() -> Unit)?>(null)
        private set
    var onRefresh by mutableStateOf<(() -> Unit)?>(null)
        private set

    val isShowing: Boolean get() = onBack != null

    fun push(title: String, onRefresh: (() -> Unit)? = null, onBack: () -> Unit) {
        this.title = title
        this.onBack = onBack
        this.onRefresh = onRefresh
    }

    fun clear() {
        title = null
        onBack = null
        onRefresh = null
    }
}
