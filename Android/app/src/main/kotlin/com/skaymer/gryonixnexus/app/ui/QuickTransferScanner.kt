package com.skaymer.gryonixnexus.app.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BinaryBitmap
import com.google.zxing.LuminanceSource
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import java.util.concurrent.Executors

/** Reads QR text out of camera frames and pictures */
object QuickTransferReader {
    fun read(source: LuminanceSource): String? =
        runCatching { QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text }.getOrNull()

    fun read(frame: ImageProxy): String? = runCatching {
        val plane = frame.planes.first()
        val bytes = ByteArray(plane.buffer.remaining()).also { plane.buffer.get(it) }
        val rows = minOf(frame.height, bytes.size / plane.rowStride)
        read(PlanarYUVLuminanceSource(bytes, plane.rowStride, rows, 0, 0, frame.width, rows, false))
    }.getOrNull()

    fun read(context: Context, uri: Uri): String? {
        val bitmap = context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream) ?: return null
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return read(RGBLuminanceSource(bitmap.width, bitmap.height, pixels))
    }
}

/** Camera with a frame, or an image instead */
@Composable
fun QuickTransferScanner(imageEmptyText: Int = R.string.quick_transfer_image_empty, onCode: (String) -> Boolean) {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(hasCamera(context)) }
    var imageProblem by remember { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed = it }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) imageProblem = !(QuickTransferReader.read(context, uri)?.let(onCode) ?: false)
    }
    LaunchedEffect(Unit) { if (!allowed) ask.launch(Manifest.permission.CAMERA) }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            Modifier.widthIn(max = 360.dp).fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(24.dp))
                .background(Color.Black.copy(alpha = 0.85f)),
            contentAlignment = Alignment.Center,
        ) {
            if (allowed) CameraPreview(onCode) else Text(stringResource(R.string.quick_transfer_no_camera), color = Color.White)
            Box(Modifier.fillMaxSize().padding(36.dp).border(4.dp, Color.White.copy(alpha = 0.8f), RoundedCornerShape(20.dp)))
        }
        PlainButton(stringResource(R.string.quick_transfer_choose_image), onClick = { pick.launch("image/*") })
        if (imageProblem) Text(stringResource(imageEmptyText), color = Gryonix.colors.danger)
    }
}

private fun hasCamera(context: Context) =
    ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

@Composable
private fun CameraPreview(onCode: (String) -> Boolean) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val view = remember { PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }
    DisposableEffect(owner) {
        val executor = Executors.newSingleThreadExecutor()
        val future = ProcessCameraProvider.getInstance(context)
        var done = false
        future.addListener({
            val provider = future.get()
            val preview = Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
            val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
            analysis.setAnalyzer(executor) { frame ->
                val text = if (done) null else QuickTransferReader.read(frame)
                frame.close()
                if (text != null) ContextCompat.getMainExecutor(context).execute { if (!done && onCode(text)) done = true }
            }
            runCatching { provider.unbindAll(); provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis) }
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            done = true
            runCatching { future.get().unbindAll() }
            executor.shutdown()
        }
    }
    AndroidView({ view }, Modifier.fillMaxSize())
}
