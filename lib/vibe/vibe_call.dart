// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:matrix/matrix.dart';

/// Voice and video calls, inside Vibe, on Jitsi Meet (open source).
///
/// Starting a call sends a small "call" message into the chat (others see a
/// card with Join, other Matrix apps see a link), then opens the call.
/// Tuned to be light: one-to-one calls go phone to phone (peer-to-peer),
/// 360p video by default (540p at most), the phone's hardware video encoder
/// (H.264), no audio-level meters or extras, and voice calls never start
/// the camera.
abstract class VibeCall {
  static const _key = 'chat.vibe.call';
  static const _channel = MethodChannel('vibe/system');

  static String get server {
    final s = AppSettings.vibeCallServer.value.trim();
    return s.isEmpty ? 'https://meet.ffmuc.net' : s;
  }

  static Map<String, Object?>? info(Event e) {
    final v = e.content[_key];
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  static String _id() {
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return 'vibe-${List.generate(20, (_) => abc[r.nextInt(abc.length)]).join()}';
  }

  /// Starts a call in [room] and joins it.
  static Future<void> start(Room room, {required bool video}) async {
    final srv = server;
    final id = _id();
    final url = '$srv/$id';
    await room.sendEvent({
      'msgtype': MessageTypes.Text,
      'body': '${video ? '📹 Video' : '📞 Voice'} call · join: $url',
      _key: {'url': url, 'server': srv, 'room': id, 'video': video},
    });
    await join(room, srv, id, video: video);
  }

  static bool _inCall = false;

  static Future<void> join(
    Room room,
    String srv,
    String id, {
    required bool video,
  }) async {
    if (_inCall) return;
    _inCall = true;
    stopRinging();
    final me = room.unsafeGetUserFromMemoryOrFallback(room.client.userID!);
    final options = JitsiMeetConferenceOptions(
      serverURL: srv,
      room: id,
      configOverrides: {
        'subject': room.getLocalizedDisplayname(),
        'startWithAudioMuted': false,
        'startWithVideoMuted': !video,
        'startAudioOnly': !video,
        'prejoinPageEnabled': false,
        'prejoinConfig.enabled': false,
        'disableDeepLinking': true,
        'requireDisplayName': false,
        // one-to-one: straight between the phones
        'p2p.enabled': true,
        'p2p.preferredCodec': 'H264',
        // hardware video encoding, modest resolution
        'videoQuality.preferredCodec': 'H264',
        'resolution': 360,
        'constraints.video.height.ideal': 360,
        'constraints.video.height.max': 540,
        'constraints.video.height.min': 180,
        'channelLastN': 4,
        'enableLayerSuspension': true,
        // fewer things running = smoother and lighter on the battery
        'disableAudioLevels': true,
        'enableNoAudioDetection': false,
        'enableNoisyMicDetection': false,
        'disableReactions': true,
        'disableInviteFunctions': true,
        'disableModeratorIndicator': true,
        'toolbarButtons': [
          'microphone',
          'camera',
          'hangup',
          'toggle-camera',
          'tileview',
        ],
      },
      featureFlags: {
        'welcomepage.enabled': false,
        'prejoinpage.enabled': false,
        'unsaferoomwarning.enabled': false,
        'chat.enabled': false,
        'invite.enabled': false,
        'add-people.enabled': false,
        'calendar.enabled': false,
        'call-integration.enabled': false,
        'car-mode.enabled': false,
        'close-captions.enabled': false,
        'live-streaming.enabled': false,
        'recording.enabled': false,
        'ios.recording.enabled': false,
        'reactions.enabled': false,
        'raise-hand.enabled': false,
        'security-options.enabled': false,
        'lobby-mode.enabled': false,
        'breakout-rooms.enabled': false,
        'speakerstats.enabled': false,
        'help.enabled': false,
        'settings.enabled': false,
        'video-share.enabled': false,
        'server-url-change.enabled': false,
        'meeting-password.enabled': false,
        'kick-out.enabled': false,
        'pip.enabled': true,
        'resolution': 360,
      },
      userInfo: JitsiMeetUserInfo(displayName: me.calcDisplayname()),
    );
    try {
      await JitsiMeet().join(
        options,
        JitsiMeetEventListener(
          conferenceTerminated: (url, error) => _inCall = false,
          readyToClose: () => _inCall = false,
        ),
      );
    } catch (e) {
      _inCall = false;
      Logs().w('Vibe call: could not join', e);
      rethrow;
    }
  }

  // ---- incoming calls ------------------------------------------------------

  static final Set<String> _seen = {};
  static StreamSubscription? _sub;

  /// Rings for a call someone just started in one of your chats.
  static void watch(Client client) {
    _sub?.cancel();
    _sub = client.onTimelineEvent.stream.listen((e) {
      final i = info(e);
      if (i == null || e.senderId == client.userID) return;
      if (!_seen.add(e.eventId)) return;
      if (DateTime.now().difference(e.originServerTs).inSeconds.abs() > 45) {
        return;
      }
      final room = e.room;
      final ctx = FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted || _inCall) return;
      _ring(ctx, room, e, i);
    });
  }

  static Timer? _ringTimer;

  static Future<void> startRinging() async {
    try {
      await _channel.invokeMethod('ring', {'on': true});
    } catch (_) {}
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      VibeHaptics.heavy();
    });
  }

  static void stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
    try {
      _channel.invokeMethod('ring', {'on': false});
    } catch (_) {}
  }

  static void _ring(BuildContext ctx, Room room, Event e, Map<String, Object?> i) {
    final video = i['video'] == true;
    final srv = i['server'] as String? ?? server;
    final id = i['room'] as String?;
    if (id == null) return;
    startRinging();
    // stop by itself after 40 s
    final auto = Timer(const Duration(seconds: 40), () {
      stopRinging();
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) nav.maybePop();
    });
    final name = e.senderFromMemoryOrFallback.calcDisplayname();
    showVibeSheet<void>(
      context: ctx,
      useRootNavigator: true,
      isDismissible: false,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(video ? Icons.videocam : Icons.call, size: 40, color: const Color(0xFF5865F2)),
              const SizedBox(height: 10),
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(video ? 'Incoming video call' : 'Incoming voice call'),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDA373C),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () {
                        auto.cancel();
                        stopRinging();
                        Navigator.of(c).pop();
                      },
                      icon: const Icon(Icons.call_end),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF23A55A),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () {
                        auto.cancel();
                        stopRinging();
                        Navigator.of(c).pop();
                        join(room, srv, id, video: video);
                      },
                      icon: Icon(video ? Icons.videocam : Icons.call),
                      label: const Text('Answer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      auto.cancel();
      stopRinging();
    });
  }

  /// Voice or video? (from the call button in a chat)
  static Future<void> pickAndStart(BuildContext context, Room room) async {
    final video = await showVibeSheet<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Voice call'),
              onTap: () => Navigator.of(c).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video call'),
              onTap: () => Navigator.of(c).pop(true),
            ),
          ],
        ),
      ),
    );
    if (video == null) return;
    try {
      await start(room, video: video);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start the call: $e')),
        );
      }
    }
  }
}

/// The card a call message shows in the chat: who called and "Join".
class VibeCallCard extends StatelessWidget {
  final Event event;
  const VibeCallCard(this.event, {super.key});

  @override
  Widget build(BuildContext context) {
    final i = VibeCall.info(event)!;
    final video = i['video'] == true;
    final cs = Theme.of(context).colorScheme;
    final fresh = DateTime.now().difference(event.originServerTs).inHours < 12;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(video ? Icons.videocam : Icons.call, color: const Color(0xFF5865F2)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              video ? 'Video call' : 'Voice call',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),
          if (fresh)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF23A55A),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => VibeCall.join(
                event.room,
                i['server'] as String? ?? VibeCall.server,
                i['room'] as String? ?? '',
                video: video,
              ),
              child: const Text('Join'),
            ),
        ],
      ),
    );
  }
}
