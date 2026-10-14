package chat.fluffy.fluffychat

import android.content.Context
import android.content.Intent
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
                    else -> result.notImplemented()
                }
            }
    }
}
