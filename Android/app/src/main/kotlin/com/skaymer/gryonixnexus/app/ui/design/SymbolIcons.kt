package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.AdminPanelSettings
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.SwapVerticalCircle
import androidx.compose.material.icons.outlined.Thermostat
import androidx.compose.material.icons.outlined.ViewDay
import androidx.compose.material.icons.outlined.Cast
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderShared
import androidx.compose.material.icons.outlined.ForwardToInbox
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.ManageSearch
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Password
import androidx.compose.material.icons.outlined.Photo
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.material.icons.outlined.Router
import androidx.compose.material.icons.outlined.Speaker
import androidx.compose.material.icons.outlined.SpeakerGroup
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.SmartDisplay
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material.icons.outlined.VpnLock
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material.icons.outlined.SdStorage
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Language
import androidx.compose.ui.graphics.vector.ImageVector

/** Material counterparts of the SF Symbols the catalogue names */
object SymbolIcons {
    private val table: Map<String, ImageVector> = mapOf(
        "arrow.triangle.branch" to Icons.Outlined.AccountTree,
        "lock.shield" to Icons.Outlined.Security,
        "square.grid.2x2" to Icons.Outlined.GridView,
        "shield.lefthalf.filled" to Icons.Outlined.Shield,
        "shield.lefthalf.filled.badge.checkmark" to Icons.Outlined.AdminPanelSettings,
        "shield.checkerboard" to Icons.Outlined.Shield,
        "point.3.filled.connected.trianglepath.dotted" to Icons.Outlined.Hub,
        "point.3.connected.trianglepath.dotted" to Icons.Outlined.Hub,
        "play.rectangle" to Icons.Outlined.SmartDisplay,
        "person.badge.key" to Icons.Outlined.Password,
        "key" to Icons.Outlined.Key,
        "key.fill" to Icons.Outlined.Key,
        "key.viewfinder" to Icons.Outlined.VpnKey,
        "house" to Icons.Outlined.Home,
        "house.fill" to Icons.Outlined.Home,
        "gamecontroller" to Icons.Outlined.SportsEsports,
        "gamecontroller.fill" to Icons.Outlined.SportsEsports,
        "cloud" to Icons.Outlined.Cloud,
        "icloud" to Icons.Outlined.Cloud,
        "chevron.left.forwardslash.chevron.right" to Icons.Outlined.Code,
        "slider.horizontal.3" to Icons.Outlined.Tune,
        "photo" to Icons.Outlined.Photo,
        "photo.stack" to Icons.Outlined.PhotoLibrary,
        "photo.on.rectangle.angled" to Icons.Outlined.Collections,
        "network" to Icons.Outlined.Public,
        "network.badge.shield.half.filled" to Icons.Outlined.VpnLock,
        "message.and.waveform" to Icons.Outlined.RecordVoiceOver,
        "magnifyingglass.circle" to Icons.Outlined.Search,
        "doc.text.magnifyingglass" to Icons.Outlined.ManageSearch,
        "gearshape" to Icons.Outlined.Settings,
        "folder" to Icons.Outlined.Folder,
        "folder.badge.person.crop" to Icons.Outlined.FolderShared,
        "eye.slash" to Icons.Outlined.VisibilityOff,
        "envelope" to Icons.Outlined.Email,
        "envelope.badge" to Icons.Outlined.MarkEmailRead,
        "envelope.badge.shield.half.filled" to Icons.Outlined.MarkEmailRead,
        "envelope.arrow.triangle.branch" to Icons.Outlined.ForwardToInbox,
        "dot.radiowaves.left.and.right" to Icons.Outlined.Wifi,
        "antenna.radiowaves.left.and.right" to Icons.Outlined.Router,
        "airplayaudio" to Icons.Outlined.Speaker,
        "airplayvideo" to Icons.Outlined.Cast,
        "hifispeaker.2" to Icons.Outlined.SpeakerGroup,
        "cylinder.split.1x2" to Icons.Outlined.Storage,
        "cpu" to Icons.Outlined.Memory,
        "bubble.left.and.text.bubble.right" to Icons.AutoMirrored.Filled.Chat,
        "brain" to Icons.Outlined.Psychology,
        "bolt.horizontal.circle" to Icons.Outlined.Bolt,
        "sparkles" to Icons.Outlined.AutoAwesome,
        "server.rack" to Icons.Outlined.Dns,
        "image" to Icons.Outlined.Image,
        "externaldrive.fill" to Icons.Outlined.SdStorage,
        "internaldrive.fill" to Icons.Outlined.Storage,
        "lock.shield.fill" to Icons.Outlined.Security,
        "envelope.fill" to Icons.Outlined.Email,
        "cloud.fill" to Icons.Outlined.Cloud,
        "bolt.horizontal.fill" to Icons.Outlined.Bolt,
        "globe" to Icons.Outlined.Language,
        "cpu.fill" to Icons.Outlined.Memory,
        "tray.full.fill" to Icons.Outlined.Inbox,
        "memorychip" to Icons.Outlined.ViewDay,
        "internaldrive" to Icons.Outlined.Storage,
        "arrow.up.arrow.down.circle" to Icons.Outlined.SwapVerticalCircle,
        "gauge.with.needle" to Icons.Outlined.Speed,
        "thermometer.medium" to Icons.Outlined.Thermostat,
        "bolt.fill" to Icons.Filled.Bolt,
    )

    fun of(symbol: String?): ImageVector = symbol?.let { table[it] } ?: Icons.Outlined.Dns
}
