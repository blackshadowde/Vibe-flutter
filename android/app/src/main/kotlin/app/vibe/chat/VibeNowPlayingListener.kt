package app.vibe.chat

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
    /**
     * Privacy: Vibe never takes any notifications. As soon as Android connects
     * this listener, Vibe disconnects it again, so no notification is ever
     * delivered to the app. Reading the music player only needs the access
     * to be switched on, not the connection.
     */
    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            requestUnbind()
        } catch (_: Throwable) {
        }
    }

    companion object {
        /** Only music apps: no videos, films or other players. */
        private val musicApps = setOf(
            "com.spotify.music",
            "com.google.android.apps.youtube.music",
            "com.apple.android.music",
            "com.jio.media.jiobeats",
            "com.gaana",
            "com.bsbportal.music",
            "com.soundcloud.android",
            "deezer.android.app",
            "com.aspiro.tidal",
            "com.amazon.mp3",
            "com.maxmpz.audioplayer",
            "in.krosbits.musicolet",
        )

        private fun isAd(title: String, artist: String): Boolean {
            val t = title.lowercase()
            val a = artist.lowercase()
            return artist.isBlank() || a == "spotify" ||
                t.contains("advertisement") || a.contains("advertisement") ||
                t == "spotify" || t.startsWith("ad ·") || t == "ad"
        }

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
                        it.packageName in musicApps
                } ?: return null
                val m = c.metadata ?: return null
                val title = m.getString(MediaMetadata.METADATA_KEY_TITLE)
                    ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                    ?: return null
                val artist = m.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
                // adverts between songs are not "listening to"
                if (isAd(title, artist)) return null
                val album = m.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
                val duration = m.getLong(MediaMetadata.METADATA_KEY_DURATION)
                // where the song is now (the player only reports it now and then)
                val ps = c.playbackState
                val position = if (ps == null) 0L else
                    ps.position + ((android.os.SystemClock.elapsedRealtime() -
                        ps.lastPositionUpdateTime) * ps.playbackSpeed).toLong()
                // a small cover for the profile card
                val art = try {
                    val bmp = m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                        ?: m.getBitmap(MediaMetadata.METADATA_KEY_ART)
                        ?: m.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
                    if (bmp == null) "" else {
                        val side = 240
                        val scaled = android.graphics.Bitmap.createScaledBitmap(bmp, side, side, true)
                        val out = java.io.ByteArrayOutputStream()
                        scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 82, out)
                        android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.NO_WRAP)
                    }
                } catch (_: Throwable) {
                    ""
                }
                val pm = context.packageManager
                val app = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(c.packageName, 0)).toString()
                } catch (_: Throwable) {
                    c.packageName
                }
                mapOf(
                    "title" to title, "artist" to artist, "app" to app,
                    "package" to c.packageName, "album" to album,
                    "duration" to duration.toString(),
                    "position" to position.coerceAtLeast(0L).toString(),
                    "art" to art,
                )
            } catch (_: Throwable) {
                null
            }
        }
    }
}
