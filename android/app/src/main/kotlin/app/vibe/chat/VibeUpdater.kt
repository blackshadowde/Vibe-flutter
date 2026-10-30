package app.vibe.chat

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
                            val sha = call.argument<String>("sha256")
                            val main = android.os.Handler(android.os.Looper.getMainLooper())
                            // reading 50 MB twice: off the main thread
                            Thread {
                                val problem = try {
                                    verify(app, dm, id, sha)
                                } catch (e: Throwable) {
                                    "Couldn't check the update"
                                }
                                main.post {
                                    try {
                                        if (problem != null) {
                                            dm.remove(id)
                                            result.error("vibe_updater", problem, null)
                                        } else {
                                            val intent = Intent(Intent.ACTION_VIEW)
                                                .setDataAndType(uri, APK_MIME)
                                                .addFlags(
                                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                                                )
                                            app.startActivity(intent)
                                            result.success(true)
                                        }
                                    } catch (e: Throwable) {
                                        result.error("vibe_updater", e.message, null)
                                    }
                                }
                            }.start()
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("vibe_updater", e.message, null)
                }
            }
    }

    /**
     * Before installing: the APK must match the SHA-256 published with the
     * release, and be signed with the same key as the installed Vibe.
     * Returns what's wrong, or null when it's safe.
     */
    private fun verify(app: Context, dm: DownloadManager, id: Long, sha256: String?): String? {
        if (sha256.isNullOrBlank()) return "No fingerprint for this update"
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        dm.openDownloadedFile(id).use { pfd ->
            java.io.FileInputStream(pfd.fileDescriptor).use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    digest.update(buf, 0, n)
                }
            }
        }
        val hex = digest.digest().joinToString("") { "%02x".format(it) }
        if (!hex.equals(sha256, ignoreCase = true)) return "The download doesn't match the release"

        // signer: copy to a readable file and compare with this app's signer
        val tmp = File(app.cacheDir, "update-check.apk")
        try {
            dm.openDownloadedFile(id).use { pfd ->
                java.io.FileInputStream(pfd.fileDescriptor).use { input ->
                    tmp.outputStream().use { input.copyTo(it) }
                }
            }
            val pm = app.packageManager
            val flags = android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
            val mine = pm.getPackageInfo(app.packageName, flags).signingInfo
                ?: return "Can't read Vibe's signature"
            val ours = (if (mine.hasMultipleSigners()) mine.apkContentsSigners else mine.signingCertificateHistory)
                .map { certId(it.toByteArray()) }.toSet()
            // some Android 10-12 phones leave signingInfo empty for APK
            // files: fall back to the older signature list
            val apk = pm.getPackageArchiveInfo(tmp.path, flags)?.signingInfo
            @Suppress("DEPRECATION")
            val theirsRaw = apk?.apkContentsSigners
                ?: pm.getPackageArchiveInfo(
                    tmp.path,
                    android.content.pm.PackageManager.GET_SIGNATURES,
                )?.signatures
                ?: return "The update isn't signed"
            val theirs = theirsRaw.map { certId(it.toByteArray()) }.toSet()
            if (theirs.intersect(ours).isEmpty()) return "The update isn't signed by Vibe"
        } finally {
            tmp.delete()
        }
        return null
    }

    private fun certId(cert: ByteArray): String =
        java.security.MessageDigest.getInstance("SHA-256").digest(cert)
            .joinToString("") { "%02x".format(it) }
}
