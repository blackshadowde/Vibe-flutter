package chat.fluffy.fluffychat

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app updater: downloads the new APK with Android's DownloadManager
 * (progress notification, keeps going if Vibe is closed) and hands it to
 * the system installer. Dart side: lib/vibe/vibe_updater.dart.
 */
object VibeUpdater {
    private const val CHANNEL = "vibe/updater"
    private const val APK_MIME = "application/vnd.android.package-archive"

    fun register(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    val dm = app.getSystemService(Context.DOWNLOAD_SERVICE)
                        as DownloadManager
                    when (call.method) {
                        "download" -> {
                            val url = call.argument<String>("url")!!
                            val name = call.argument<String>("name")!!
                            // Remove an old copy so the file keeps its name.
                            File(
                                app.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                                name,
                            ).delete()
                            val request = DownloadManager.Request(Uri.parse(url))
                                .setTitle("Vibe update")
                                .setDescription(name)
                                .setMimeType(APK_MIME)
                                .setNotificationVisibility(
                                    DownloadManager.Request.VISIBILITY_VISIBLE,
                                )
                                .setDestinationInExternalFilesDir(
                                    app,
                                    Environment.DIRECTORY_DOWNLOADS,
                                    name,
                                )
                            result.success(dm.enqueue(request))
                        }
                        "status" -> {
                            val id = (call.argument<Number>("id")!!).toLong()
                            val cursor = dm.query(DownloadManager.Query().setFilterById(id))
                            cursor.use {
                                if (!it.moveToFirst()) {
                                    result.success(mapOf("status" to "missing"))
                                    return@setMethodCallHandler
                                }
                                val status = it.getInt(
                                    it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS),
                                )
                                val done = it.getLong(
                                    it.getColumnIndexOrThrow(
                                        DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
                                    ),
                                )
                                val total = it.getLong(
                                    it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                                )
                                val s = when (status) {
                                    DownloadManager.STATUS_SUCCESSFUL -> "done"
                                    DownloadManager.STATUS_FAILED -> "failed"
                                    DownloadManager.STATUS_PAUSED -> "paused"
                                    else -> "running"
                                }
                                result.success(
                                    mapOf("status" to s, "done" to done, "total" to total),
                                )
                            }
                        }
                        "cancel" -> {
                            val id = (call.argument<Number>("id")!!).toLong()
                            dm.remove(id)
                            result.success(true)
                        }
                        "canInstall" -> {
                            val allowed =
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    app.packageManager.canRequestPackageInstalls()
                                } else {
                                    true
                                }
                            result.success(allowed)
                        }
                        "allowInstall" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:" + app.packageName),
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                app.startActivity(intent)
                            }
                            result.success(true)
                        }
                        "install" -> {
                            val id = (call.argument<Number>("id")!!).toLong()
                            val uri = dm.getUriForDownloadedFile(id)
                            if (uri == null) {
                                result.error("vibe_updater", "Download not found", null)
                                return@setMethodCallHandler
                            }
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, APK_MIME)
                                .addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                                )
                            app.startActivity(intent)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("vibe_updater", e.message, null)
                }
            }
    }
}
