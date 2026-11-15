package com.skaymer.gryonixnexus.app.ui

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ai.AiImageStore
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

const val AI_MAX_ATTACHMENTS = 4

/** Glass message field with attach and send buttons */
@Composable
internal fun AiChatInputBar(
    draft: String,
    onChange: (String) -> Unit,
    attachments: List<ByteArray>,
    onAttachments: (List<ByteArray>) -> Unit,
    streaming: Boolean,
    onStop: () -> Unit,
    onSend: () -> Unit,
) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)
            .aiGlass(RoundedCornerShape(24.dp)).padding(6.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (attachments.isNotEmpty()) AttachmentStrip(attachments, onAttachments)
        Row(verticalAlignment = Alignment.Bottom) {
            AttachMenu(attachments, onAttachments)
            DraftField(draft, onChange, Modifier.weight(1f))
            val ready = draft.isNotBlank() || attachments.isNotEmpty()
            if (streaming) {
                RoundAction(Icons.Filled.Stop, stringResource(R.string.ai_stop), Gryonix.colors.secondaryLabel, true, onStop)
            } else {
                RoundAction(Icons.Filled.ArrowUpward, stringResource(R.string.ai_send),
                    if (ready) Gryonix.colors.accent else Gryonix.colors.tertiaryLabel, ready, onSend)
            }
        }
    }
}

@Composable
private fun DraftField(draft: String, onChange: (String) -> Unit, modifier: Modifier) {
    Box(modifier.padding(horizontal = 4.dp, vertical = 9.dp)) {
        if (draft.isEmpty()) {
            Text(stringResource(R.string.ai_ask_about), style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.tertiaryLabel)
        }
        BasicTextField(
            draft, onChange, maxLines = 6, modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = Gryonix.colors.label),
            cursorBrush = SolidColor(Gryonix.colors.accent),
        )
    }
}

@Composable
private fun AttachMenu(attachments: List<ByteArray>, onAttachments: (List<ByteArray>) -> Unit) {
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    val room = (AI_MAX_ATTACHMENTS - attachments.size).coerceAtLeast(1)
    val add: (List<Uri>) -> Unit = { uris ->
        val loaded = uris.mapNotNull { uri -> readPicture(context, uri) }
        onAttachments((attachments + loaded).take(AI_MAX_ATTACHMENTS))
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxOf(2, room))) { add(it) }
    Box {
        IconButton(onClick = { open = true }, enabled = attachments.size < AI_MAX_ATTACHMENTS, modifier = Modifier.size(40.dp)) {
            Icon(Icons.Filled.Add, stringResource(R.string.ai_attach), tint = Gryonix.colors.secondaryLabel)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.ai_photo_library)) },
                leadingIcon = { Icon(Icons.Outlined.PhotoLibrary, null) },
                onClick = {
                    open = false
                    picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                },
            )
            val clipped = remember(open) { clipboardPicture(context) }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.ai_paste_picture)) },
                leadingIcon = { Icon(Icons.Outlined.ContentPaste, null) },
                enabled = clipped != null,
                onClick = { open = false; clipped?.let { add(listOf(it)) } },
            )
        }
    }
}

/** The clipboard's picture, when it holds one */
private fun clipboardPicture(context: Context): Uri? {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return null
    val clip = clipboard.primaryClip ?: return null
    if (clip.itemCount == 0 || clip.description?.hasMimeType("image/*") != true) return null
    return clip.getItemAt(0).uri
}

private fun readPicture(context: Context, uri: Uri): ByteArray? = runCatching {
    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }?.let { AiImageStore.jpeg(it) }
}.getOrNull()

@Composable
private fun AttachmentStrip(attachments: List<ByteArray>, onAttachments: (List<ByteArray>) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        attachments.forEachIndexed { index, bytes ->
            Box {
                AiPicture(bytes, Modifier.size(64.dp).clip(RoundedCornerShape(14.dp)))
                IconButton(
                    onClick = { onAttachments(attachments.filterIndexed { i, _ -> i != index }) },
                    modifier = Modifier.align(Alignment.TopEnd).size(24.dp),
                ) {
                    Icon(Icons.Filled.Close, stringResource(R.string.ai_remove_picture), tint = Color.White,
                        modifier = Modifier.size(20.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.6f)).padding(3.dp))
                }
            }
        }
    }
}

/** JPEG bytes drawn as a cropped picture */
@Composable
internal fun AiPicture(bytes: ByteArray, modifier: Modifier) {
    val bitmap = remember(bytes) { android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
    if (bitmap != null) Image(bitmap, null, modifier, contentScale = ContentScale.Crop)
}

@Composable
private fun RoundAction(icon: ImageVector, label: String, fill: Color, enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(40.dp)) {
        Box(Modifier.size(34.dp).clip(CircleShape).background(fill), contentAlignment = Alignment.Center) {
            Icon(icon, label, tint = Color.White, modifier = Modifier.size(18.dp))
        }
    }
}
