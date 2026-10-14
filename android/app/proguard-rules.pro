-keep class net.sqlcipher.** { *; }
# Calls (LiveKit / WebRTC native code looks these up by name)
-keep class org.webrtc.** { *; }
-keep class io.livekit.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
