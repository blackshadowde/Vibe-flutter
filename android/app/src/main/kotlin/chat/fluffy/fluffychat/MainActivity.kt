package chat.fluffy.fluffychat

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import android.content.Context
import android.os.Build

class MainActivity : FlutterFragmentActivity() {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    /** Floating call window (picture-in-picture) while a call is on. */
    fun enterCallPip(): Boolean {
        return try {
            enterPictureInPictureMode(
                android.app.PictureInPictureParams.Builder()
                    .setAspectRatio(android.util.Rational(9, 16))
                    .build()
            )
        } catch (_: Throwable) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (VibeSystemNative.callActive) enterCallPip()
    }

    override fun onResume() {
        super.onResume()
        current = this
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

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    /** Android's "save to" picker (Google Drive, OneDrive, phone) for the backup file. */
    fun pickBackupPlace(name: String) {
        try {
            val i = android.content.Intent(android.content.Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(android.content.Intent.CATEGORY_OPENABLE)
                .setType("application/octet-stream")
                .putExtra(android.content.Intent.EXTRA_TITLE, name)
            @Suppress("DEPRECATION")
            startActivityForResult(i, PICK_BACKUP)
        } catch (_: Throwable) {
            VibeBackupNative.picked(this, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_BACKUP) {
            VibeBackupNative.picked(this, if (resultCode == RESULT_OK) data?.data else null)
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // do nothing, because the engine was been configured in provideEngine
    }

    companion object {
        private const val PICK_BACKUP = 4711
        var current: MainActivity? = null
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
