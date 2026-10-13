package chat.fluffy.fluffychat

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.drinkless.tdlib.JsonClient

/**
 * Telegram inside Vibe (Dart side: lib/vibe/telegram/).
 *
 * A thin bridge to Telegram's official TDLib (JSON interface): Dart sends
 * JSON requests, and one background thread hands every answer and update
 * back as JSON. TDLib itself (libtdjsonjava.so) is built from source by the
 * "Build TDLib" workflow and added to the app at build time.
 */
object VibeTelegramNative {
    private const val CHANNEL = "vibe/telegram"
    private const val EVENTS = "vibe/telegram/updates"

    @Volatile private var running = false
    private var receiver: Thread? = null

    fun register(context: Context, engine: FlutterEngine) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // TDLib version, or null when the library isn't in this build.
                        "available" -> result.success(version())
                        "create" -> result.success(JsonClient.createClientId())
                        "send" -> {
                            JsonClient.send(
                                call.argument<Int>("client")!!,
                                call.argument<String>("request")!!,
                            )
                            result.success(null)
                        }
                        "execute" -> result.success(JsonClient.execute(call.argument<String>("request")!!))
                        else -> result.notImplemented()
                    }
                } catch (e: UnsatisfiedLinkError) {
                    result.error("unavailable", "Telegram isn't included in this build", null)
                } catch (e: Throwable) {
                    result.error("failed", e.message, null)
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    if (running) return
                    running = true
                    receiver = Thread {
                        while (running) {
                            val json = try {
                                JsonClient.receive(1.0)
                            } catch (e: Throwable) {
                                running = false
                                null
                            }
                            if (json != null) main.post { sink.success(json) }
                        }
                    }.apply {
                        name = "vibe-telegram"
                        isDaemon = true
                        start()
                    }
                }

                override fun onCancel(arguments: Any?) {
                    running = false
                    receiver = null
                }
            })
    }

    private fun version(): String? = try {
        // Quiet TDLib's own logging (errors only).
        JsonClient.execute("{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":1}")
        val answer = JsonClient.execute("{\"@type\":\"getOption\",\"name\":\"version\"}")
        Regex("\"value\":\"([^\"]+)\"").find(answer ?: "")?.groupValues?.get(1) ?: "unknown"
    } catch (e: Throwable) {
        null
    }
}
