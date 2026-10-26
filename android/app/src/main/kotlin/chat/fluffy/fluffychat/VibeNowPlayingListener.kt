package chat.fluffy.fluffychat

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.service.notification.NotificationListenerService
import androidx.core.app.NotificationManagerCompat

/**
 * Lets Vibe see which song is playing in any music app (Spotify, YouTube
 * Music, ...) for the "Listening to" status. Android only shares media
 * sessions with an enabled notification listener; it reads nothing else.
 */
class VibeNowPlayingListener : NotificationListenerService() {
    companion object {
        fun hasAccess(context: Context): Boolean =
            NotificationManagerCompat.getEnabledListenerPackages(context)
                .contains(context.packageName)

        /** The playing track: title, artist, app; null when nothing plays. */
        fun current(context: Context): Map<String, String>? {
            if (!hasAccess(context)) return null
            return try {
                val msm = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
                val sessions = msm.getActiveSessions(
                    ComponentName(context, VibeNowPlayingListener::class.java)
                )
                val c = sessions.firstOrNull {
                    it.playbackState?.state == PlaybackState.STATE_PLAYING &&
                        it.packageName != context.packageName
                } ?: return null
                val m = c.metadata ?: return null
                val title = m.getString(MediaMetadata.METADATA_KEY_TITLE)
                    ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                    ?: return null
                val artist = m.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
                val pm = context.packageManager
                val app = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(c.packageName, 0)).toString()
                } catch (_: Throwable) {
                    c.packageName
                }
                mapOf("title" to title, "artist" to artist, "app" to app, "package" to c.packageName)
            } catch (_: Throwable) {
                null
            }
        }
    }
}
