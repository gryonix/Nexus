package com.skaymer.gryonixnexus.app.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import androidx.annotation.RawRes
import androidx.annotation.StringRes
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.SettingsStore

/** The kinds of alert a sound can be chosen for */
enum class NotifySoundGroup(val raw: String, @StringRes val title: Int) {
    DISKS("disks", R.string.notify_disks),
    SERVICES("services", R.string.notify_services),
    BACKUPS("backups", R.string.notify_backups),
    AGENT("agent", R.string.notify_agent_update),
    OPERATIONS("operations", R.string.notify_operations),
    SSH("ssh", R.string.notify_ssh_logins);

    companion object {
        /** The group of an alert kind such as `gnx.alert.backup.ok` */
        fun of(kind: String): NotifySoundGroup? = when (kind.removePrefix("gnx.alert.").substringBefore('.')) {
            "raid", "smart", "space", "drive_readonly", "drive_stale" -> DISKS
            "service" -> SERVICES
            "backup" -> BACKUPS
            "agent_update" -> AGENT
            "operation" -> OPERATIONS
            "ssh_login" -> SSH
            else -> null
        }.takeIf { kind.startsWith("gnx.alert.") }
    }
}

/** A sound this app carries, the system's, or none */
enum class NotifySound(val raw: String, @StringRes val title: Int, @RawRes val file: Int?) {
    STANDARD("default", R.string.sound_default, null),
    NONE("none", R.string.sound_none, null),
    CHIME("chime", R.string.sound_chime, R.raw.chime),
    BELL("bell", R.string.sound_bell, R.raw.bell),
    DROP("drop", R.string.sound_drop, R.raw.drop),
    PULSE("pulse", R.string.sound_pulse, R.raw.pulse),
    ALARM("alarm", R.string.sound_alarm, R.raw.alarm);

    /** Plays it once, as a preview */
    fun play(context: Context) {
        when {
            this == NONE -> Unit
            file == null -> RingtoneManager.getRingtone(
                context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            )?.play()
            else -> MediaPlayer.create(context, file)?.apply { setOnCompletionListener { it.release() } }?.start()
        }
    }

    companion object {
        fun of(raw: String?): NotifySound = entries.firstOrNull { it.raw == raw } ?: STANDARD
    }
}

/** This device's sound per kind of alert */
object NotifySounds {
    fun key(group: NotifySoundGroup): String = "notify.sound.${group.raw}"

    fun sound(store: SettingsStore, group: NotifySoundGroup): NotifySound = NotifySound.of(store.string(key(group)))

    fun set(store: SettingsStore, group: NotifySoundGroup, sound: NotifySound) = store.setString(key(group), sound.raw)

    /** The channel for this kind, made on first use */
    fun channel(context: Context, store: SettingsStore?, kind: String, fallback: String): String {
        val group = NotifySoundGroup.of(kind) ?: return fallback
        val sound = store?.let { sound(it, group) } ?: NotifySound.STANDARD
        if (sound == NotifySound.STANDARD) return fallback
        val id = "$fallback.${group.raw}.${sound.raw}"
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(id) == null) {
            val channel = NotificationChannel(id, context.getString(group.title), NotificationManager.IMPORTANCE_HIGH)
            val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
            channel.setSound(sound.file?.let { Uri.parse("android.resource://${context.packageName}/$it") }, attributes)
            manager.createNotificationChannel(channel)
        }
        return id
    }
}
