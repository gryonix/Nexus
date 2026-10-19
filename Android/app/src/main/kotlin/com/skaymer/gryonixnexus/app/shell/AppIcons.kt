package com.skaymer.gryonixnexus.app.shell

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/** The home-screen icon colours, one launcher alias each */
enum class AppIcon(val raw: String) {
    BLUE("blue"),
    RED("red"),
    ORANGE("orange"),
    YELLOW("yellow"),
    GREEN("green"),
    TEAL("teal"),
    PURPLE("purple"),
    PINK("pink"),
    GRAPHITE("graphite"),
    BLACK("black"),
    INDIGO("indigo"),
    BROWN("brown");

    /** The manifest alias that shows this icon */
    val alias: String get() = "com.skaymer.gryonixnexus.app.Launcher" + raw.replaceFirstChar { it.uppercase() }
}

object AppIcons {
    /** The icon the launcher shows now */
    fun current(context: Context): AppIcon {
        val packages = context.packageManager
        return AppIcon.entries.firstOrNull { icon ->
            val state = packages.getComponentEnabledSetting(ComponentName(context, icon.alias))
            state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && icon == AppIcon.BLUE)
        } ?: AppIcon.BLUE
    }

    /** Shows the chosen icon; the others step aside */
    fun choose(context: Context, chosen: AppIcon) {
        val packages = context.packageManager
        packages.setComponentEnabledSetting(
            ComponentName(context, chosen.alias),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        AppIcon.entries.filter { it != chosen }.forEach { other ->
            packages.setComponentEnabledSetting(
                ComponentName(context, other.alias),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
