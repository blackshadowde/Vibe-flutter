package chat.fluffy.fluffychat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * After the phone restarts (or Vibe is updated), start Vibe quietly in the
 * background so its connection comes back and notifications keep arriving
 * without opening the app. Dart side: main() with "vibe-boot".
 */
class VibeBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return
        try {
            val eng = MainActivity.provideEngine(context)
            if (!eng.dartExecutor.isExecutingDart) {
                eng.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault(),
                    listOf("vibe-boot"),
                )
            }
        } catch (e: Throwable) {
            Log.w("VibeBoot", "Could not start Vibe in the background", e)
        }
    }
}
