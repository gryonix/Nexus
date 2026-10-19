package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

class PushedScreen {
    var title by mutableStateOf<String?>(null)
        private set
    var onBack by mutableStateOf<(() -> Unit)?>(null)
        private set

    val isShowing: Boolean get() = onBack != null

    fun push(title: String, onBack: () -> Unit) {
        this.title = title
        this.onBack = onBack
    }

    fun clear() {
        title = null
        onBack = null
    }
}
