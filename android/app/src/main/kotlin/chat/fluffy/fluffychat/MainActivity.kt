package chat.fluffy.fluffychat

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import android.content.Context
import android.os.Build

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun onResume() {
        super.onResume()
        requestHighRefreshRate()
    }

    // Ask Android for the highest refresh rate (90/120 Hz) at the current
    // resolution instead of letting the system pick 60 Hz.
    @Suppress("DEPRECATION")
    private fun requestHighRefreshRate() {
        try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                this.display
            } else {
                windowManager.defaultDisplay
            } ?: return
            val current = display.mode
            val best = display.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return
            val params = window.attributes
            params.preferredDisplayModeId = best.modeId
            window.attributes = params
        } catch (_: Throwable) {
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            engine?.let { return it }
            // The engine outlives any one screen (Android rebuilds the
            // screen on theme / colour changes), so it must not hold on to
            // the first Activity: use the app context.
            val app = context.applicationContext
            VibeSystemNative.installCrashRecorder(app)
            val eng = FlutterEngine(app, emptyArray(), true, false)
            eng.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}
                override fun onEngineWillDestroy() {
                    if (engine === eng) engine = null
                }
            })
            VibeUpdater.register(context, eng)
            VibeBackupNative.register(context, eng)
            VibeSystemNative.register(context, eng)
            engine = eng
            return eng
        }
    }
}
