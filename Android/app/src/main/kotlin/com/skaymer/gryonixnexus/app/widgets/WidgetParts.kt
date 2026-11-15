package com.skaymer.gryonixnexus.app.widgets

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.action.actionStartActivity
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.ImageProvider
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.skaymer.gryonixnexus.R
import androidx.glance.appwidget.AndroidRemoteViews
import android.widget.RemoteViews
import com.skaymer.gryonixnexus.app.MainActivity

/** The rounded card; a tap opens the app */
@Composable
fun WidgetFrame(content: @Composable () -> Unit) {
    Box(
        GlanceModifier.fillMaxSize().cornerRadius(20.dp).background(ImageProvider(R.drawable.widget_frame))
            .padding(14.dp).clickable(actionStartActivity<MainActivity>()),
    ) { content() }
}

@Composable
fun WidgetText(
    text: String,
    size: TextUnit = 12.sp,
    weight: FontWeight = FontWeight.Normal,
    color: Color? = null,
    secondary: Boolean = false,
    maxLines: Int = 1,
) {
    val provider = color?.let { ColorProvider(it) }
        ?: if (secondary) GlanceTheme.colors.onSurfaceVariant else GlanceTheme.colors.onSurface
    Text(text, style = TextStyle(fontSize = size, fontWeight = weight, color = provider), maxLines = maxLines)
}

/** Verdict dot, title, headline, detail and age */
@Composable
fun StatusCard(verdict: WidgetPresentation.Verdict, title: String, headline: String, detail: String?, age: String?) {
    WidgetFrame {
        Column(GlanceModifier.fillMaxSize()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                WidgetText("●", size = 12.sp, color = WidgetPresentation.tint(verdict), secondary = true)
                Spacer(GlanceModifier.width(4.dp))
                WidgetText(title, secondary = true)
            }
            Spacer(GlanceModifier.height(6.dp))
            WidgetText(headline, size = 18.sp, weight = FontWeight.Bold, maxLines = 2)
            detail?.let {
                Spacer(GlanceModifier.height(4.dp))
                WidgetText(it, secondary = true, maxLines = 2)
            }
            Spacer(GlanceModifier.defaultWeight())
            age?.let { WidgetText(it, size = 11.sp, secondary = true) }
        }
    }
}

/** What a widget says before the app read anything */
@Composable
fun UnavailableCard(title: String, available: Boolean, hint: Int = R.string.widget_open_server_once) {
    val context = LocalContext.current
    WidgetFrame {
        Column(GlanceModifier.fillMaxSize()) {
            WidgetText(title, secondary = true)
            Spacer(GlanceModifier.height(4.dp))
            WidgetText(context.getString(if (available) R.string.widget_nothing_read else R.string.widget_open_app), size = 13.sp)
            Spacer(GlanceModifier.height(2.dp))
            WidgetText(context.getString(hint), size = 11.sp, secondary = true, maxLines = 3)
        }
    }
}

/** A labelled share drawn as a filled track */
@Composable
fun LoadBar(name: String, percent: Double?) {
    val share = ((percent ?: 0.0) / 100).coerceIn(0.0, 1.0).toFloat()
    Column(GlanceModifier.fillMaxWidth()) {
        Row(GlanceModifier.fillMaxWidth()) {
            WidgetText(name, size = 11.sp, secondary = true)
            Spacer(GlanceModifier.defaultWeight())
            WidgetText(WidgetPresentation.percent(percent), size = 11.sp)
        }
        Spacer(GlanceModifier.height(2.dp))
        TintedBar(share, percent)
    }
}

/** A bar in the load colour, on every Android */
@Composable
private fun TintedBar(share: Float, percent: Double?) {
    val layout = when (WidgetPresentation.loadTint(percent)) {
        WidgetPresentation.GREEN -> R.layout.widget_bar_green
        WidgetPresentation.ORANGE -> R.layout.widget_bar_orange
        WidgetPresentation.RED -> R.layout.widget_bar_red
        else -> R.layout.widget_bar_none
    }
    val views = RemoteViews(LocalContext.current.packageName, layout)
    views.setProgressBar(R.id.widget_bar, 100, (share * 100).toInt(), false)
    AndroidRemoteViews(views, GlanceModifier.fillMaxWidth().height(4.dp))
}
