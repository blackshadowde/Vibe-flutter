package app.vibe.chat

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Vibe chat backups (Dart side: lib/vibe/vibe_backup.dart).
 *
 * - Encryption: AES-256-GCM with a key made from your backup password by
 *   PBKDF2-HMAC-SHA256 (310,000 rounds, random salt). Without the password
 *   the file can't be read; a changed file is refused.
 *   File layout: "VIBEBK1" | salt (16) | iv (12) | encrypted data.
 * - Saving: Downloads/Vibe backups, so backups survive uninstalling Vibe.
 *   Automatic backups keep only the newest few.
 */
object VibeBackupNative {
    private const val CHANNEL = "vibe/backup"
    private val MAGIC = "VIBEBK1".toByteArray(Charsets.US_ASCII)
    private const val ROUNDS = 310_000
    private const val FOLDER = "Vibe backups"
    private const val MIME = "application/octet-stream"
    private val random = SecureRandom()

    fun register(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                // Google Drive (or any app's) backup file, picked once with Android's "save to" picker
                if (call.method == "pickCloud") {
                    val act = MainActivity.current
                    if (act == null) {
                        result.error("failed", "Open Vibe first", null)
                    } else {
                        pending?.success(null)
                        pending = result
                        act.pickBackupPlace(call.argument<String>("name") ?: "vibe-backup.vibebackup")
                    }
                    return@setMethodCallHandler
                }
                // PBKDF2 and file work take a moment: never on the UI thread.
                Thread {
                    try {
                        val value: Any? = when (call.method) {
                            "encrypt" -> encrypt(
                                call.argument<String>("password")!!,
                                call.argument<ByteArray>("data")!!,
                            )
                            "decrypt" -> decrypt(
                                call.argument<String>("password")!!,
                                call.argument<ByteArray>("data")!!,
                            )
                            "save" -> save(
                                app,
                                call.argument<String>("name")!!,
                                call.argument<ByteArray>("data")!!,
                                call.argument<String>("keepPrefix"),
                                call.argument<Int>("keep") ?: 0,
                            )
                            "saveCloud" -> {
                                val u = android.net.Uri.parse(call.argument<String>("uri")!!)
                                val data = call.argument<ByteArray>("data")!!
                                val cr = app.contentResolver
                                // "wt" empties the old backup first; some providers only know "w"
                                val out = runCatching { cr.openOutputStream(u, "wt") }.getOrNull()
                                    ?: cr.openOutputStream(u, "w")
                                    ?: throw IllegalStateException("The backup file can't be opened. Choose where to keep it again.")
                                out.use { it.write(data) }
                                cloudName(app, u) ?: "Google Drive"
                            }
                            "cloudName" -> cloudName(app, android.net.Uri.parse(call.argument<String>("uri")!!))
                            else -> {
                                main.post { result.notImplemented() }
                                return@Thread
                            }
                        }
                        main.post { result.success(value) }
                    } catch (e: WrongPassword) {
                        main.post { result.error("wrong_password", "Wrong password", null) }
                    } catch (e: NotABackup) {
                        main.post { result.error("not_backup", "Not a Vibe backup", null) }
                    } catch (e: Throwable) {
                        main.post { result.error("failed", e.message, null) }
                    }
                }.start()
            }
    }

    var pending: MethodChannel.Result? = null

    /** The picked place (kept across restarts), or null if cancelled. */
    fun picked(context: Context, uri: android.net.Uri?) {
        val r = pending ?: return
        pending = null
        if (uri == null) return r.success(null)
        try {
            context.contentResolver.takePersistableUriPermission(
                uri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: Throwable) {
        }
        r.success(uri.toString())
    }

    /** "Google Drive · vibe-backup.vibebackup", or null if the file is gone. */
    private fun cloudName(context: Context, u: android.net.Uri): String? {
        val name = context.contentResolver.query(u, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        } ?: return null
        val a = u.authority ?: ""
        val where = when {
            a.contains("com.google.android.apps.docs") -> "Google Drive"
            a.contains("onedrive") || a.contains("skydrive") -> "OneDrive"
            a.contains("dropbox") -> "Dropbox"
            else -> "This phone"
        }
        return "$where · $name"
    }

    private class WrongPassword : Exception()
    private class NotABackup : Exception()

    private fun key(password: String, salt: ByteArray): SecretKeySpec {
        val spec = PBEKeySpec(password.toCharArray(), salt, ROUNDS, 256)
        val bytes = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        spec.clearPassword()
        return SecretKeySpec(bytes, "AES")
    }

    private fun encrypt(password: String, data: ByteArray): ByteArray {
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val iv = ByteArray(12).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(password, salt), GCMParameterSpec(128, iv))
        cipher.updateAAD(MAGIC)
        return MAGIC + salt + iv + cipher.doFinal(data)
    }

    private fun decrypt(password: String, data: ByteArray): ByteArray {
        if (data.size < MAGIC.size + 16 + 12 + 16 ||
            !data.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)
        ) {
            throw NotABackup()
        }
        val salt = data.copyOfRange(MAGIC.size, MAGIC.size + 16)
        val iv = data.copyOfRange(MAGIC.size + 16, MAGIC.size + 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(password, salt), GCMParameterSpec(128, iv))
        cipher.updateAAD(MAGIC)
        try {
            return cipher.doFinal(data, MAGIC.size + 28, data.size - MAGIC.size - 28)
        } catch (e: javax.crypto.AEADBadTagException) {
            throw WrongPassword()
        }
    }

    /** Saves to Downloads/Vibe backups and returns where it went. */
    private fun save(
        context: Context,
        name: String,
        data: ByteArray,
        keepPrefix: String?,
        keep: Int,
    ): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, MIME)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + FOLDER)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values) ?: throw IllegalStateException("Could not create file")
            resolver.openOutputStream(uri)!!.use { it.write(data) }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            if (keepPrefix != null && keep > 0) {
                // Our own automatic backups, newest first: delete beyond [keep].
                val projection = arrayOf(android.provider.BaseColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME)
                val sel = MediaStore.MediaColumns.RELATIVE_PATH + " LIKE ? AND " +
                    MediaStore.MediaColumns.DISPLAY_NAME + " LIKE ?"
                val args = arrayOf("%" + FOLDER + "%", "$keepPrefix%")
                resolver.query(collection, projection, sel, args, MediaStore.MediaColumns.DATE_ADDED + " DESC")?.use { c ->
                    var i = 0
                    while (c.moveToNext()) {
                        i++
                        if (i > keep) {
                            val id = c.getLong(0)
                            resolver.delete(
                                android.content.ContentUris.withAppendedId(collection, id),
                                null,
                                null,
                            )
                        }
                    }
                }
            }
            return "Downloads/$FOLDER/$name"
        }
        // Older Android: Vibe's own folder in Downloads.
        val dir = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), FOLDER)
        dir.mkdirs()
        File(dir, name).writeBytes(data)
        if (keepPrefix != null && keep > 0) {
            dir.listFiles { f -> f.name.startsWith(keepPrefix) }
                ?.sortedByDescending { it.lastModified() }
                ?.drop(keep)
                ?.forEach { it.delete() }
        }
        return dir.absolutePath + "/" + name
    }
}
