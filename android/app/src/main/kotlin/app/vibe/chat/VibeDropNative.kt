package app.vibe.chat

import android.app.Activity
import android.content.ClipDescription
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.DragEvent
import android.view.View
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Drag and drop from other apps (a screenshot preview, Photos, Files in split
 * screen) onto Vibe. The dropped photos and videos are copied into Vibe's
 * cache and handed to the open chat (Dart: lib/vibe/vibe_drop.dart).
 */
object VibeDropNative {
    private const val CHANNEL = "vibe/drop"
    private var channel: MethodChannel? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    }

    private fun wanted(d: ClipDescription?): Boolean =
        d != null && (d.hasMimeType("image/*") || d.hasMimeType("video/*"))

    fun attach(activity: Activity) {
        val main = Handler(Looper.getMainLooper())
        activity.window.decorView.setOnDragListener(View.OnDragListener { _, e ->
            when (e.action) {
                DragEvent.ACTION_DRAG_STARTED -> wanted(e.clipDescription)
                DragEvent.ACTION_DRAG_ENTERED -> {
                    channel?.invokeMethod("enter", null)
                    true
                }
                DragEvent.ACTION_DRAG_EXITED, DragEvent.ACTION_DRAG_ENDED -> {
                    channel?.invokeMethod("exit", null)
                    true
                }
                DragEvent.ACTION_DROP -> {
                    val clip = e.clipData ?: return@OnDragListener false
                    // lets Vibe read files from the other app for this drop
                    val perms = try {
                        activity.requestDragAndDropPermissions(e)
                    } catch (_: Throwable) {
                        null
                    }
                    val uris = (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
                    Thread {
                        val files = uris.mapNotNull { copy(activity, it) }
                        try {
                            perms?.release()
                        } catch (_: Throwable) {
                        }
                        main.post { channel?.invokeMethod("drop", files) }
                    }.start()
                    true
                }
                else -> true
            }
        })
    }

    /**
     * desktop_drop (used for desktop) also listens on Android, on the content
     * view inside the window, so it got drops first and handed the chat a
     * content:// link it can't open ("Cannot open file"). Vibe handles
     * Android drops above, so its listener is removed. Called on every
     * resume: the plugin sets it again when the screen is rebuilt.
     */
    fun silenceDesktopDrop(activity: Activity) {
        activity.findViewById<View>(android.R.id.content)?.setOnDragListener(null)
    }

    private fun copy(activity: Activity, uri: Uri): Map<String, String>? = try {
        val cr = activity.contentResolver
        val mime = cr.getType(uri) ?: "application/octet-stream"
        var name: String? = null
        cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) name = it.getString(0)
        }
        val ext = mime.substringAfter('/', "bin").substringBefore(';')
        val fileName = (name ?: "drop_${System.currentTimeMillis()}.$ext")
            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val dir = File(activity.cacheDir, "drops").apply { mkdirs() }
        val out = File(dir, "${System.nanoTime()}_$fileName")
        cr.openInputStream(uri)?.use { input ->
            out.outputStream().use { input.copyTo(it) }
        } ?: throw IllegalStateException("no stream")
        mapOf("path" to out.absolutePath, "mime" to mime, "name" to fileName)
    } catch (_: Throwable) {
        null
    }
}
