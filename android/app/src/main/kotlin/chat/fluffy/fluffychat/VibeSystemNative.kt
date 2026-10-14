package chat.fluffy.fluffychat

import android.content.Context
import android.content.Intent
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
                    "isSpeaker" -> result.success(isSpeaker(app))
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
}
