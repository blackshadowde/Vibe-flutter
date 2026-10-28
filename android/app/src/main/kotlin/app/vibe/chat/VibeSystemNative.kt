package app.vibe.chat

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.util.Log
import java.io.File
import java.util.Date
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Small system shortcuts for Vibe (Dart side: lib/vibe/vibe_hide_service.dart).
 *
 * "openChannelSettings": opens Android's settings for one of Vibe's
 * notification categories, e.g. the "Vibe connection" one, so it can be
 * turned off in one tap. Android keeps Vibe's background connection
 * running; only the permanent notification disappears.
 *
 * "setSpeaker": during a call, play through the loudspeaker (true) or the
 * earpiece / headset (false). "isSpeaker" reads the current route.
 */
object VibeSystemNative {
    private const val CHANNEL = "vibe/system"

    private var ringtone: android.media.Ringtone? = null

    /** A call is on screen: leaving the app shrinks it into a floating window. */
    @Volatile var callActive = false

    fun register(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openChannelSettings" -> {
                        val id = call.argument<String>("channel") ?: ""
                        try {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && id.isNotEmpty()) {
                                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName)
                                    .putExtra(Settings.EXTRA_CHANNEL_ID, id)
                            } else {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName)
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            app.startActivity(intent)
                            result.success(true)
                        } catch (e: Throwable) {
                            result.success(false)
                        }
                    }
                    "setSpeaker" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        result.success(setSpeaker(app, on))
                    }
                    // incoming call: the phone's ringtone (Dart: VibeCall)
                    "ring" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        try {
                            ringtone?.stop()
                            ringtone = null
                            if (on) {
                                val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
                                ringtone = android.media.RingtoneManager.getRingtone(app, uri)?.also { it.play() }
                            }
                        } catch (_: Throwable) {
                        }
                        result.success(null)
                    }
                    // now playing status (Dart: VibeNowPlaying)
                    "nowPlaying" -> result.success(VibeNowPlayingListener.current(app))
                    "hasNotificationAccess" -> result.success(VibeNowPlayingListener.hasAccess(app))
                    "openNotificationAccess" -> {
                        try {
                            app.startActivity(
                                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (_: Throwable) {
                        }
                        result.success(null)
                    }
                    "callActive" -> {
                        callActive = call.argument<Boolean>("on") ?: false
                        result.success(null)
                    }
                    "pip" -> result.success(MainActivity.current?.enterCallPip() ?: false)
                    "isSpeaker" -> result.success(isSpeaker(app))
                    "lastExit" -> result.success(lastExit(app))
                    // Hypr Launcher's theme (Dart: VibeGlass.followLauncher)
                    "hyprTheme" -> {
                        try {
                            app.contentResolver.query(
                                android.net.Uri.parse("content://app.hypr.theme/current"),
                                null, null, null, null,
                            )?.use { c ->
                                if (c.moveToFirst()) {
                                    result.success(mapOf("palette" to c.getString(0)))
                                } else {
                                    result.success(null)
                                }
                            } ?: result.success(null)
                        } catch (_: Throwable) {
                            result.success(null)
                        }
                    }
                    "resetAudio" -> {
                        try {
                            val am = audio(app)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                am.clearCommunicationDevice()
                            } else {
                                @Suppress("DEPRECATION")
                                am.isSpeakerphoneOn = false
                            }
                            am.mode = AudioManager.MODE_NORMAL
                        } catch (e: Throwable) {
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun audio(context: Context) =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun setSpeaker(context: Context, on: Boolean): Boolean {
        val am = audio(context)
        return try {
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (on) {
                    val speaker = am.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                    }
                    if (speaker != null) am.setCommunicationDevice(speaker) else false
                } else {
                    am.clearCommunicationDevice()
                    true
                }
            } else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = on
                true
            }
        } catch (e: Throwable) {
            false
        }
    }

    private fun isSpeaker(context: Context): Boolean {
        val am = audio(context)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.communicationDevice?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            } else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn
            }
        } catch (e: Throwable) {
            false
        }
    }

    // ---- crash reports ----

    private const val CRASH_FILE = "vibe_last_crash.txt"
    private var crashRecorderInstalled = false

    /** Writes any uncaught Kotlin/Java crash to a file before the app dies. */
    fun installCrashRecorder(app: Context) {
        if (crashRecorderInstalled) return
        crashRecorderInstalled = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                File(app.filesDir, CRASH_FILE).writeText(
                    "${Date()}\nthread: ${thread.name}\n${Log.getStackTraceString(error)}"
                )
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }

    /**
     * Why Vibe last stopped, if it crashed or froze: Android keeps this
     * (Android 11+), including native crashes we can't catch ourselves.
     */
    private fun lastExit(context: Context): Map<String, Any?>? {
        val java = try {
            File(context.filesDir, CRASH_FILE).takeIf { it.exists() }?.readText()
        } catch (_: Throwable) {
            null
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return if (java == null) null else mapOf(
                "time" to File(context.filesDir, CRASH_FILE).lastModified(),
                "reason" to "crash",
                "description" to "",
                "trace" to java,
            )
        }
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = am.getHistoricalProcessExitReasons(context.packageName, 0, 8)
                .firstOrNull {
                    it.reason == ApplicationExitInfo.REASON_CRASH ||
                        it.reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
                        it.reason == ApplicationExitInfo.REASON_ANR
                } ?: return null
            val reason = when (info.reason) {
                ApplicationExitInfo.REASON_CRASH -> "crash"
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "native crash"
                else -> "not responding"
            }
            var trace: String? = null
            try {
                info.traceInputStream?.use { stream ->
                    val bytes = stream.readBytes()
                    trace = if (info.reason == ApplicationExitInfo.REASON_ANR) {
                        String(bytes).take(30000)
                    } else {
                        readable(bytes)
                    }
                }
            } catch (_: Throwable) {
            }
            if (info.reason == ApplicationExitInfo.REASON_CRASH && java != null) {
                trace = java
            }
            mapOf(
                "time" to info.timestamp,
                "reason" to reason,
                "description" to (info.description ?: ""),
                "trace" to (trace ?: ""),
            )
        } catch (e: Throwable) {
            null
        }
    }

    /** Native crash reports are binary; keep the readable lines. */
    private fun readable(bytes: ByteArray): String {
        val out = StringBuilder()
        val run = StringBuilder()
        for (b in bytes) {
            val c = b.toInt() and 0xff
            if (c in 32..126) {
                run.append(c.toChar())
            } else {
                if (run.length >= 6) out.append(run).append('\n')
                run.setLength(0)
            }
            if (out.length > 30000) break
        }
        if (run.length >= 6) out.append(run)
        return out.toString()
    }
}
