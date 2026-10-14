// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:fluffychat/vibe/call/vibe_call_keys.dart';
import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:fluffychat/vibe/call/vibe_rtc_session.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

enum VibeCallStage { idle, connecting, inCall, leaving }

/// One person's picture in the call: camera, screen share, speaking.
class VibeCallTile {
  final String participantId;
  final String userId;
  final bool local;
  final lk.VideoTrack? camera;
  final lk.VideoTrack? screen;
  final bool speaking;
  final bool muted;

  const VibeCallTile({
    required this.participantId,
    required this.userId,
    required this.local,
    required this.camera,
    required this.screen,
    required this.speaking,
    required this.muted,
  });
}

/// Native voice / video calls (Vibe 3.1). Same calls as Element Call,
/// Element X and Sable (MatrixRTC on a LiveKit call server), but run by
/// Vibe itself: LiveKit's Flutter SDK carries the audio and video, and
/// Vibe writes the Matrix side (membership, ringing, encryption keys).
class VibeCall extends ChangeNotifier {
  VibeCall._();
  static final VibeCall instance = VibeCall._();

  static const _system = MethodChannel('vibe/system');

  Room? room;
  VibeCallStage stage = VibeCallStage.idle;

  lk.Room? _lk;
  lk.EventsListener<lk.RoomEvent>? _lkEvents;
  VibeRtcSession? _session;
  VibeCallKeys? _keys;
  StreamSubscription? _stateSub;
  StreamSubscription? _declineSub;
  final Set<String> _ringEventIds = {};
  Timer? _noAnswer;

  /// Bumped on every start and hang-up, so a start that's still running
  /// when you hang up notices and undoes itself.
  int _gen = 0;

  /// Full screen (true) or the green bar (false).
  bool expanded = true;

  bool micOn = true;
  bool videoOn = false;
  bool soundOn = true;
  bool speakerOn = false;
  bool screenOn = false;
  bool frontCamera = true;
  bool _wantVideo = false;
  bool _hadService = false;

  /// Your video big and theirs small (tap your video, like WhatsApp).
  bool swapped = false;

  DateTime? joinedAt;

  /// Show the video view (video calls, or "show video" in a voice call).
  /// Otherwise Vibe's voice call screen is shown.
  bool showStage = false;
  bool _stageDismissed = false;

  /// Something went wrong before the call connected.
  String? problem;

  /// What happened during the call, for "Copy call log".
  final List<String> log = [];

  void _log(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    log.add('$t $line');
    if (log.length > 400) log.removeRange(0, log.length - 400);
    Logs().v('[Vibe call] $line');
  }

  Future<void> copyLog() async {
    final head = [
      'Vibe call log (native)',
      'room: ${room?.id}',
      'server: ${room?.client.homeserver}',
      'stage: ${stage.name}',
      'call service: ${_serviceUrl ?? VibeCallSupport.lastServiceUrl ?? 'none found'}',
      'encrypted: ${room?.encrypted}, keys received: ${_keys?.receivedCount ?? 0}',
    ];
    await Clipboard.setData(ClipboardData(text: [...head, ...log].join('\n')));
    _snack('Call log copied');
  }

  String? _serviceUrl;

  /// People in the call other than you (from Matrix).
  List<String> get others {
    final r = room;
    if (r == null) return const [];
    final me = r.client.userID;
    return VibeCallMembers.userIds(r).where((u) => u != me).toList();
  }

  bool get active => room != null && stage != VibeCallStage.idle;
  bool isIn(Room r) => active && room?.id == r.id;

  String get roomName => room?.getLocalizedDisplayname() ?? 'Call';

  static BuildContext? get _navContext =>
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;

  static void _snack(String text) {
    final ctx = _navContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------
  // Pictures
  // ---------------------------------------------------------------------

  static String _userOf(String identity) {
    // "@user:server:DEVICE" -> "@user:server"
    final i = identity.lastIndexOf(':');
    if (i <= 0 || !identity.startsWith('@')) return identity;
    final first = identity.indexOf(':');
    return i == first ? identity : identity.substring(0, i);
  }

  static lk.VideoTrack? _video(lk.Participant p, lk.TrackSource source) {
    for (final pub in p.videoTrackPublications) {
      if (pub.source != source || pub.muted) continue;
      final t = pub.track;
      if (t is lk.VideoTrack) return t;
    }
    return null;
  }

  /// Everyone's picture, you first.
  List<VibeCallTile> get tiles {
    final r = _lk;
    if (r == null) return const [];
    final out = <VibeCallTile>[];
    final me = r.localParticipant;
    if (me != null) {
      out.add(
        VibeCallTile(
          participantId: me.identity,
          userId: room?.client.userID ?? _userOf(me.identity),
          local: true,
          camera: videoOn ? _video(me, lk.TrackSource.camera) : null,
          screen: _video(me, lk.TrackSource.screenShareVideo),
          speaking: me.isSpeaking,
          muted: !micOn,
        ),
      );
    }
    for (final p in r.remoteParticipants.values) {
      out.add(
        VibeCallTile(
          participantId: p.identity,
          userId: _userOf(p.identity),
          local: false,
          camera: _video(p, lk.TrackSource.camera),
          screen: _video(p, lk.TrackSource.screenShareVideo),
          speaking: p.isSpeaking,
          muted: p.isMuted,
        ),
      );
    }
    return out;
  }

  int get _remoteVideo =>
      tiles.where((t) => !t.local && (t.camera != null || t.screen != null)).length;

  void _onLiveKitChange() {
    if (_remoteVideo > 0 && !showStage && !_stageDismissed && expanded) {
      showStage = true;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Start / join
  // ---------------------------------------------------------------------

  /// Join (or start) the call in [room].
  static Future<void> join(
    BuildContext context,
    Room room, {
    bool video = false,
  }) async {
    final call = instance;
    if (call.isIn(room)) {
      call.expand();
      return;
    }
    if (call.active) {
      final name = call.roomName;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Switch call?'),
          content: Text('You\'ll leave the call in $name.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await call.hangup();
    }
    if (!context.mounted) return;
    if (!await VibeCallSupport.ensure(context, room)) return;
    if (!context.mounted) return;
    if (!await VibeCallPower.ensureAllowed(context, room)) return;
    if (PlatformInfos.isMobile) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        _snack(
          mic.isPermanentlyDenied
              ? 'Allow the microphone for Vibe in Android settings to call.'
              : 'Vibe needs the microphone for calls.',
        );
        if (mic.isPermanentlyDenied) await openAppSettings();
        return;
      }
      if (video) {
        final cam = await Permission.camera.request();
        if (!cam.isGranted) video = false;
      }
    }
    await call._start(room, video: video);
  }

  Future<void> _start(Room room, {required bool video}) async {
    final client = room.client;
    final gen = ++_gen;
    bool gone() => gen != _gen;
    this.room = room;
    stage = VibeCallStage.connecting;
    expanded = true;
    micOn = true;
    videoOn = video;
    _wantVideo = video;
    soundOn = true;
    screenOn = false;
    swapped = false;
    frontCamera = true;
    // Earpiece for one-to-one voice calls, loudspeaker for video / groups.
    speakerOn = video || !room.isDirectChat;
    _stageDismissed = false;
    showStage = video;
    joinedAt = null;
    problem = null;
    _handEventId = null;
    reactions.value = const [];
    log.clear();
    _log('start ${room.id} video=$video encrypted=${room.encrypted}');
    notifyListeners();
    VibeHaptics.medium();
    unawaited(_startService());

    try {
      try {
        await room.postLoad();
        final count = room.summary.mJoinedMemberCount ?? 0;
        if (count > 0 && count <= 300) {
          await room.requestParticipants([Membership.join]);
        }
      } catch (e) {
        _log('could not load members: $e');
      }

      // 1) Which call server? The one the call already uses (the oldest
      //    membership's), else your own server's.
      final me = '${client.userID}:${client.deviceID}';
      final existing = VibeCallMembers.sessions(
        room,
      ).where((m) => m.participantId != me).toList();
      final first = existing.isEmpty ? null : existing.first.focus;
      final own = await VibeCallSupport.serviceUrl(client);
      final url = first?.url ?? own;
      if (url == null) {
        throw const _CallProblem(
          'Your server doesn\'t offer Matrix calls, and nobody else is in '
          'this call yet.',
        );
      }
      final alias = (first?.alias.isNotEmpty ?? false) ? first!.alias : room.id;
      _serviceUrl = url;
      final foci = <Map<String, Object?>>[
        {'type': 'livekit', 'livekit_service_url': url, 'livekit_alias': alias},
        if (own != null && own != url)
          {
            'type': 'livekit',
            'livekit_service_url': own,
            'livekit_alias': room.id,
          },
      ];
      _log('call server $url (${first != null ? 'from the call' : 'yours'})');

      // 2) A LiveKit pass for that server, via your Matrix OpenID token.
      final openId = await client.requestOpenIdToken(client.userID!, {});
      final res = await client.httpClient.post(
        Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/sfu/get'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'room': alias,
          'openid_token': openId.toJson(),
          'device_id': client.deviceID,
        }),
      );
      if (res.statusCode != 200) {
        throw _CallProblem(
          'The call server said no (${res.statusCode}). Try again in a bit.',
        );
      }
      final sfu = jsonDecode(res.body) as Map<String, Object?>;
      final sfuUrl = sfu['url'] as String?;
      final jwt = sfu['jwt'] as String?;
      if (sfuUrl == null || jwt == null) {
        throw const _CallProblem('The call server sent an odd answer.');
      }
      _log('got call pass for $sfuUrl');
      if (gone()) return; // hung up meanwhile

      // 3) Encryption keys (Element Call compatible).
      VibeCallKeys? keys;
      if (room.encrypted) {
        keys = await VibeCallKeys.create(
          client: client,
          roomId: room.id,
          log: _log,
        );
        keys.start();
        _keys = keys;
      }

      // 4) Connect to the call server.
      await lk.AudioManager.instance.setSpeakerOutputPreferred(speakerOn);
      final lkRoom = lk.Room(
        roomOptions: lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: const lk.AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
            // cuts low hum and handling noise
            highPassFilter: true,
            voiceIsolation: true,
          ),
          defaultCameraCaptureOptions: const lk.CameraCaptureOptions(
            params: lk.VideoParametersPresets.h720_169,
          ),
          defaultScreenShareCaptureOptions: const lk.ScreenShareCaptureOptions(
            useiOSBroadcastExtension: false,
            params: lk.VideoParametersPresets.screenShareH1080FPS15,
          ),
          // Media encryption only, like Element Call (the newer
          // `encryption` option also encrypts data messages, which Element
          // Call doesn't expect).
          // ignore: deprecated_member_use
          e2eeOptions: keys == null
              ? null
              : lk.E2EEOptions(keyProvider: keys.keyProvider),
        ),
      );
      _lk = lkRoom;
      keys?.onOwnKey = (index) async =>
          lkRoom.e2eeManager?.setKeyIndex(index);
      lkRoom.addListener(_onLiveKitChange);
      final events = lkRoom.createListener();
      _lkEvents = events;
      events
        ..on<lk.RoomDisconnectedEvent>((e) {
          _log('call server disconnected: ${e.reason}');
          if (stage == VibeCallStage.inCall) {
            _snack('Call ended: connection lost');
            unawaited(hangup());
          }
        })
        ..on<lk.RoomReconnectingEvent>((_) => _log('reconnecting'))
        ..on<lk.RoomReconnectedEvent>((_) => _log('reconnected'))
        ..on<lk.ParticipantConnectedEvent>(
          (e) => _log('joined: ${e.participant.identity}'),
        )
        ..on<lk.ParticipantDisconnectedEvent>(
          (e) => _log('left: ${e.participant.identity}'),
        )
        ..on<lk.TrackSubscribedEvent>((e) {
          _log('${e.participant.identity}: ${e.publication.source.name}');
          if (!soundOn) _applySound();
        })
        ..on<lk.TrackE2EEStateEvent>(
          (e) => _log('e2ee ${e.participant.identity}: ${e.state.name}'),
        )
        ..on<lk.TrackPublishedEvent>(
          (e) => _log(
            '${e.participant.identity} published ${e.publication.source.name}',
          ),
        )
        ..on<lk.TrackMutedEvent>(
          (e) => _log(
            '${e.participant.identity} muted ${e.publication.source.name}',
          ),
        )
        ..on<lk.TrackUnmutedEvent>(
          (e) => _log(
            '${e.participant.identity} unmuted ${e.publication.source.name}',
          ),
        )
        // Cameras turned on later, mutes, new tracks: redraw on any change
        // (the room itself only reports some of them).
        ..listen((_) => _onLiveKitChange());
      await lkRoom.connect(sfuUrl, jwt);
      _log('connected to the call server');
      if (gone()) {
        await lkRoom.disconnect();
        return;
      }
      final local = lkRoom.localParticipant;
      _log(
        'my call identity ${local?.identity} '
        '(keys for ${client.userID}:${client.deviceID}), '
        'already there: ${lkRoom.remoteParticipants.keys.join(', ')}',
      );
      await local?.setMicrophoneEnabled(true);
      if (video) {
        try {
          await local?.setCameraEnabled(true);
        } catch (e) {
          videoOn = false;
          _log('camera failed: $e');
        }
      }
      await _applySpeaker();

      // 5) Tell Matrix you're in the call.
      final session = VibeRtcSession(
        room: room,
        fociPreferred: foci,
        intent: video ? 'video' : 'audio',
        log: _log,
      );
      _session = session;
      await session.join();
      if (gone()) {
        // hung up while joining: take the membership back
        await session.leave();
        return;
      }
      _stateSub = client.onRoomState.stream
          .where(
            (u) =>
                u.roomId == room.id &&
                u.state.type == VibeCallMembers.memberType,
          )
          .listen((_) => _membershipsChanged());
      _membershipsChanged();

      // 6) Ring them if you're the first one in.
      if (existing.isEmpty && !VibeCallMembers.isVoiceRoom(room)) {
        final dm = room.isDirectChat;
        _ringEventIds
          ..clear()
          ..addAll(await session.notify(ring: dm));
        if (gone()) return;
        if (dm) _watchRing(room);
      }

      _markJoined();
    } on _CallProblem catch (e) {
      _log('problem: ${e.message}');
      problem = e.message;
      notifyListeners();
    } catch (e, s) {
      _log('failed: $e');
      Logs().w('Vibe call failed', e, s);
      problem =
          'The call didn\'t connect. Copy the call log and send it to '
          'support so we can see what went wrong.';
      notifyListeners();
    }
  }

  void _membershipsChanged() {
    final r = room;
    if (r == null) return;
    final members = VibeCallMembers.sessions(r);
    _keys?.update(members);
    final me = r.client.userID;
    if (members.any((m) => m.userId != me)) _noAnswer?.cancel();
    notifyListeners();
  }

  /// Outgoing DM call: stop when declined, or after 30 s with no answer.
  void _watchRing(Room room) {
    _noAnswer?.cancel();
    _noAnswer = Timer(const Duration(seconds: 35), () {
      if (isIn(room) && others.isEmpty) {
        _snack('No answer');
        unawaited(hangup());
      }
    });
    _declineSub?.cancel();
    _declineSub = room.client.onTimelineEvent.stream
        .where(
          (e) =>
              e.roomId == room.id &&
              e.type == VibeCallMembers.declineType &&
              e.senderId != room.client.userID,
        )
        .listen((e) {
          // While it's still ringing (they haven't joined), any decline
          // from them ends it, whichever of our ring events it points at.
          if (others.isNotEmpty) return;
          _log('declined by ${e.senderId}');
          _snack('Call declined');
          unawaited(hangup());
        });
  }

  void _markJoined() {
    if (stage == VibeCallStage.inCall || stage == VibeCallStage.leaving) {
      return;
    }
    stage = VibeCallStage.inCall;
    joinedAt = DateTime.now();
    problem = null;
    VibeHaptics.light();
    _watchAlone();
    _listenReactions();
    notifyListeners();
    final r = room;
    if (r != null) unawaited(markCallRead(r));
  }

  /// Call events (the ring, "joined", "declined") count as unread on the
  /// server but never show in the chat, which left a stuck "1" on the
  /// picture. Mark the chat read up to its newest event.
  static Future<void> markCallRead(Room room) async {
    try {
      final res = await room.client.getRoomEvents(
        room.id,
        Direction.b,
        limit: 1,
      );
      final id = res.chunk.isEmpty ? null : res.chunk.first.eventId;
      if (id == null) return;
      await room.setReadMarker(id, mRead: id);
    } catch (e) {
      Logs().v('Vibe call: could not mark read $e');
    }
  }

  // ---------------------------------------------------------------------
  // Ending
  // ---------------------------------------------------------------------

  /// One-to-one calls end when the other person leaves (like a phone call).
  Timer? _aloneTimer;
  bool _sawOthers = false;
  int _aloneTicks = 0;

  void _watchAlone() {
    _aloneTimer?.cancel();
    _sawOthers = false;
    _aloneTicks = 0;
    _aloneTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final r = room;
      if (r == null || !active) return;
      final n = others.length;
      if (n > 0) {
        _sawOthers = true;
        _aloneTicks = 0;
        return;
      }
      if (!_sawOthers || !r.isDirectChat || stage != VibeCallStage.inCall) {
        return;
      }
      if (++_aloneTicks >= 2) {
        _log('the other person left, ending the call');
        _snack('Call ended');
        unawaited(hangup());
      }
    });
  }

  /// Call memberships of this device left behind by an earlier run of the
  /// app (killed mid-call, crashed) make chats show a call forever. Clear
  /// them once at start.
  static Future<void> cleanupStale(Client client) async {
    final device = client.deviceID;
    final me = client.userID;
    if (device == null || me == null) return;
    for (final r in client.rooms) {
      if (instance.isIn(r)) continue;
      final states = r.states[VibeCallMembers.memberType];
      if (states == null) continue;
      for (final e in states.entries.toList()) {
        if (e.value.senderId != me ||
            e.value.content.isEmpty ||
            !e.key.contains(device)) {
          continue;
        }
        Logs().i('Vibe call: clearing old call membership in ${r.id}');
        try {
          await client.setRoomStateWithKey(
            r.id,
            VibeCallMembers.memberType,
            e.key,
            {},
          );
        } catch (err) {
          Logs().v('Vibe call: could not clear $err');
        }
      }
    }
  }

  /// Leave the call.
  Future<void> hangup() async {
    if (!active || stage == VibeCallStage.leaving) return;
    _gen++;
    _ringEventIds.clear();
    VibeHaptics.medium();
    stage = VibeCallStage.leaving;
    notifyListeners();
    _aloneTimer?.cancel();
    _noAnswer?.cancel();
    await _declineSub?.cancel();
    _declineSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _reactionSub?.cancel();
    _reactionSub = null;

    final lkRoom = _lk;
    final session = _session;
    final keys = _keys;
    final r = room;
    _lk = null;
    _session = null;
    _keys = null;
    _lkEvents?.dispose();
    _lkEvents = null;
    lkRoom?.removeListener(_onLiveKitChange);

    // Tell Matrix first, so the chat stops showing the call right away.
    try {
      await session?.leave().timeout(const Duration(seconds: 8));
    } catch (e) {
      _log('leave: $e');
    }
    try {
      await lkRoom?.disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await lkRoom?.dispose();
    } catch (_) {}
    keys?.dispose();

    room = null;
    stage = VibeCallStage.idle;
    joinedAt = null;
    expanded = true;
    showStage = false;
    screenOn = false;
    swapped = false;
    _handEventId = null;
    reactions.value = const [];
    notifyListeners();
    if (PlatformInfos.isAndroid) {
      try {
        await _system.invokeMethod('resetAudio');
      } catch (_) {}
    }
    await _stopService();
    if (r != null) {
      Future<void>.delayed(const Duration(seconds: 3), () => markCallRead(r));
    }
  }

  // ---------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------

  void expand() {
    if (!active) return;
    expanded = true;
    notifyListeners();
  }

  void minimize() {
    if (!active) return;
    expanded = false;
    notifyListeners();
  }

  void toggleStage() {
    if (!active) return;
    showStage = !showStage;
    if (!showStage) _stageDismissed = true;
    notifyListeners();
  }

  void toggleSwap() {
    if (!active) return;
    VibeHaptics.selection();
    swapped = !swapped;
    notifyListeners();
  }

  Future<void> toggleMic() async {
    if (!active) return;
    VibeHaptics.selection();
    micOn = !micOn;
    if (micOn && !soundOn) {
      soundOn = true;
      _applySound();
    }
    notifyListeners();
    try {
      await _lk?.localParticipant?.setMicrophoneEnabled(micOn);
    } catch (e) {
      _log('mic: $e');
    }
  }

  Future<void> toggleVideo() async {
    if (!active) return;
    VibeHaptics.selection();
    if (!videoOn && PlatformInfos.isMobile) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _snack('Vibe needs the camera for video.');
        return;
      }
      if (!_wantVideo) {
        _wantVideo = true;
        unawaited(_startService());
      }
    }
    videoOn = !videoOn;
    if (videoOn) showStage = true;
    notifyListeners();
    try {
      await _lk?.localParticipant?.setCameraEnabled(
        videoOn,
        cameraCaptureOptions: lk.CameraCaptureOptions(
          cameraPosition: frontCamera
              ? lk.CameraPosition.front
              : lk.CameraPosition.back,
          params: lk.VideoParametersPresets.h720_169,
        ),
      );
    } catch (e) {
      videoOn = false;
      _log('camera: $e');
      notifyListeners();
    }
    if (videoOn && !speakerOn) await setSpeaker(true);
  }

  Future<void> flipCamera() async {
    final me = _lk?.localParticipant;
    if (me == null || !videoOn) return;
    VibeHaptics.selection();
    for (final pub in me.videoTrackPublications) {
      final t = pub.track;
      if (pub.source == lk.TrackSource.camera && t is lk.LocalVideoTrack) {
        frontCamera = !frontCamera;
        try {
          await t.setCameraPosition(
            frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back,
          );
        } catch (e) {
          _log('flip camera: $e');
        }
      }
    }
    notifyListeners();
  }

  /// Share your screen (Android asks first, then shows "Vibe is sharing").
  Future<void> toggleScreenShare() async {
    final me = _lk?.localParticipant;
    if (me == null || stage != VibeCallStage.inCall) {
      _snack('Wait until the call has connected.');
      return;
    }
    VibeHaptics.selection();
    if (screenOn) {
      screenOn = false;
      notifyListeners();
      try {
        await me.setScreenShareEnabled(false);
      } catch (e) {
        _log('stop screen share: $e');
      }
      return;
    }
    if (PlatformInfos.isAndroid) {
      final ok = await rtc.Helper.requestCapturePermission();
      if (!ok) return;
      // Android needs a "screen capture" service before capturing.
      await _startService(screen: true);
    }
    try {
      await me.setScreenShareEnabled(true, captureScreenAudio: false);
      screenOn = true;
      showStage = true;
      _log('sharing screen');
    } catch (e) {
      _log('screen share failed: $e');
      _snack('Couldn\'t share your screen.');
    }
    notifyListeners();
  }

  /// Deafen, Discord style: hear nobody, and your mic goes off too.
  void toggleSound() {
    if (!active) return;
    VibeHaptics.selection();
    soundOn = !soundOn;
    _applySound();
    if (!soundOn && micOn) {
      micOn = false;
      unawaited(
        _lk?.localParticipant?.setMicrophoneEnabled(false) ?? Future.value(),
      );
    }
    notifyListeners();
  }

  void _applySound() {
    final r = _lk;
    if (r == null) return;
    for (final p in r.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final t = pub.track;
        if (t != null) t.mediaStreamTrack.enabled = soundOn;
      }
    }
  }

  Future<void> setSpeaker(bool on) async {
    speakerOn = on;
    notifyListeners();
    await _applySpeaker();
  }

  Future<void> _applySpeaker() async {
    try {
      await lk.AudioManager.instance.setSpeakerOutputPreferred(
        speakerOn,
        force: speakerOn,
      );
    } catch (e) {
      _log('speaker switch failed: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Reactions and raised hand (Element Call's format)
  // ---------------------------------------------------------------------

  /// Send an emoji reaction to everyone in the call.
  /// Your current membership event (what Element Call matches reactions
  /// and raised hands against).
  String? get _ownMembershipEventId {
    final r = room;
    if (r == null) return null;
    final me = '${r.client.userID}:${r.client.deviceID}';
    for (final m in VibeCallMembers.sessions(r)) {
      if (m.participantId == me && m.eventId != null) return m.eventId;
    }
    return _session?.membershipEventId;
  }

  Future<void> react(String emoji, String name) async {
    final r = room;
    final target = _ownMembershipEventId;
    if (r == null || target == null || stage != VibeCallStage.inCall) {
      _snack('Reactions work once the call has connected.');
      return;
    }
    VibeHaptics.light();
    reactions.value = [
      ...reactions.value,
      VibeCallReaction(emoji, r.client.userID!),
    ];
    try {
      final id = await r.sendEvent(
        {
          'm.relates_to': {'rel_type': 'm.reference', 'event_id': target},
          'emoji': emoji,
          'name': name,
        },
        type: VibeCallReaction.type,
        displayPendingEvent: false,
      );
      _log('reaction $name sent $id (to $target)');
    } catch (e) {
      _log('reaction failed: $e');
    }
  }

  String? _handEventId;
  bool get handRaised => _handEventId != null;

  Future<void> toggleHand() async {
    final r = room;
    final target = _ownMembershipEventId;
    if (r == null || target == null || stage != VibeCallStage.inCall) {
      _snack('Wait until the call has connected.');
      return;
    }
    VibeHaptics.selection();
    final old = _handEventId;
    if (old == '') return; // still sending
    if (old != null) {
      _handEventId = null;
      notifyListeners();
      try {
        await r.redactEvent(old);
      } catch (e) {
        _log('lower hand failed: $e');
      }
      return;
    }
    _handEventId = '';
    notifyListeners();
    try {
      _handEventId = await r.sendEvent(
        {
          'm.relates_to': {
            'rel_type': 'm.annotation',
            'event_id': target,
            'key': '🖐️',
          },
        },
        type: EventTypes.Reaction,
        displayPendingEvent: false,
      );
    } catch (e) {
      _handEventId = null;
      _log('raise hand failed: $e');
    }
    notifyListeners();
  }

  /// Reactions to float up the call screen (yours and other people's).
  final ValueNotifier<List<VibeCallReaction>> reactions = ValueNotifier(
    const [],
  );
  StreamSubscription? _reactionSub;

  void _listenReactions() {
    final room = this.room;
    if (room == null) return;
    _reactionSub?.cancel();
    _reactionSub = room.client.onTimelineEvent.stream
        .where(
          (e) =>
              e.roomId == room.id &&
              e.type == VibeCallReaction.type &&
              e.senderId != room.client.userID,
        )
        .listen((e) {
          final emoji = e.content['emoji'];
          if (emoji is! String || emoji.isEmpty) return;
          if (DateTime.now().difference(e.originServerTs).inSeconds > 20) {
            return;
          }
          reactions.value = [
            ...reactions.value,
            VibeCallReaction(emoji, e.senderId),
          ];
        });
  }

  // ---------------------------------------------------------------------
  // Keep the call alive with the screen off
  // ---------------------------------------------------------------------

  Future<void> _startService({bool screen = false}) async {
    if (!PlatformInfos.isAndroid) return;
    try {
      final running = await FlutterForegroundTask.isRunningService;
      if (running && !_hadServiceChecked) {
        _hadService = true;
      }
      _hadServiceChecked = true;
      if (running) await FlutterForegroundTask.stopService();
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'vibe_call',
          channelName: 'Calls',
          channelDescription: 'Shows while you are in a call',
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showWhen: true,
          priority: NotificationPriority.LOW,
          channelImportance: NotificationChannelImportance.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
        ),
      );
      final camera = _wantVideo && await Permission.camera.isGranted;
      await FlutterForegroundTask.startService(
        serviceTypes: [
          ForegroundServiceTypes.microphone,
          if (camera) ForegroundServiceTypes.camera,
          if (screen || screenOn) ForegroundServiceTypes.mediaProjection,
        ],
        notificationTitle: 'Vibe call',
        notificationText: screen
            ? 'Sharing your screen · $roomName'
            : 'In a call · $roomName',
        notificationIcon: NotificationIcon(metaDataName: 'ic_launcher'),
      );
    } catch (e, s) {
      Logs().w('Vibe call: foreground service failed', e, s);
    }
  }

  bool _hadServiceChecked = false;

  Future<void> _stopService() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
      if (_hadService || ForegroundServices.runningServices.isNotEmpty) {
        await ForegroundServices.resume();
      }
    } catch (e) {
      Logs().w('Vibe call: could not restore service', e);
    }
    _hadService = false;
    _hadServiceChecked = false;
  }
}

class _CallProblem implements Exception {
  final String message;
  const _CallProblem(this.message);
}

/// An emoji someone sent during the call.
class VibeCallReaction {
  static const type = 'io.element.call.reaction';

  /// The same set Element Call offers, so both sides show the same thing.
  static const choices = <(String, String)>[
    ('👍', 'thumbsup'),
    ('👎', 'thumbsdown'),
    ('🥰', 'heart'),
    ('😄', 'laugh'),
    ('🎉', 'party'),
    ('👏', 'clapping'),
    ('👌', 'ok'),
    ('🤘', 'rock'),
    ('👋', 'wave'),
    ('💡', 'lightbulb'),
    ('😵‍💫', 'dizzy'),
    ('🐶', 'dog'),
    ('🐱', 'cat'),
    ('🦗', 'crickets'),
  ];

  final String emoji;
  final String sender;
  final int id;
  static int _seq = 0;
  VibeCallReaction(this.emoji, this.sender) : id = ++_seq;
}

/// Calls need everyone to be allowed to post their "I'm in the call" state.
/// Matrix rooms block that for normal members by default, so Vibe opens it
/// up when creating groups, and asks admins to switch it on for old ones.
abstract class VibeCallPower {
  /// Default Matrix power levels for state events, plus call membership
  /// for everyone (use as `powerLevelContentOverride` when creating rooms).
  static Map<String, Object?> get createOverride => {
    'events': {
      'm.room.name': 50,
      'm.room.avatar': 50,
      'm.room.canonical_alias': 50,
      'm.room.topic': 50,
      'm.room.power_levels': 100,
      'm.room.history_visibility': 100,
      'm.room.encryption': 100,
      'm.room.tombstone': 100,
      'm.room.server_acl': 100,
      'm.space.child': 50,
      'm.room.pinned_events': 50,
      VibeCallMembers.memberType: 0,
      'org.matrix.msc3401.call': 50,
    },
  };

  static bool allowed(Room room) =>
      room.canChangeStateEvent(VibeCallMembers.memberType);

  static Future<bool> ensureAllowed(BuildContext context, Room room) async {
    if (allowed(room)) return true;
    if (!room.canChangePowerLevel) {
      _snack('Calls are off in this group. Ask an admin to turn them on.');
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn on calls?'),
        content: const Text(
          'This group only lets admins join calls. Turn calls on so '
          'everyone in it can join?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      final content = Map<String, Object?>.from(
        room.getState(EventTypes.RoomPowerLevels)?.content ?? const {},
      );
      final events = Map<String, Object?>.from(
        content['events'] as Map? ?? const {},
      );
      events[VibeCallMembers.memberType] = 0;
      content['events'] = events;
      await room.client.setRoomStateWithKey(
        room.id,
        EventTypes.RoomPowerLevels,
        '',
        content,
      );
      return true;
    } catch (e) {
      _snack('Couldn\'t turn on calls: $e');
      return false;
    }
  }

  static void _snack(String text) => VibeCall._snack(text);
}

/// Does your server offer Matrix calls? Element Call needs a call service
/// (a LiveKit "focus") announced by the server. Without one you can still
/// join calls other people start (they bring their own), but you can't
/// start one.
abstract class VibeCallSupport {
  /// What the last check found (shown in the call log).
  static String? lastServiceUrl;

  static final Map<String, (DateTime, String?)> _cache = {};

  /// The call service URL for [client]'s server, or null if it has none.
  static Future<String?> serviceUrl(Client client) async {
    final key = client.homeserver.toString();
    final hit = _cache[key];
    if (hit != null &&
        DateTime.now().difference(hit.$1) < const Duration(minutes: 10)) {
      return hit.$2;
    }
    String? url;
    String? pick(Object? list) {
      if (list is! List) return null;
      for (final f in list) {
        if (f is Map && f['type'] == 'livekit') {
          final u = f['livekit_service_url'];
          if (u is String && u.isNotEmpty) return u;
        }
      }
      return null;
    }

    try {
      final wk = await client.getWellknown();
      url = pick(wk.additionalProperties['org.matrix.msc4143.rtc_foci']);
    } catch (e) {
      Logs().v('Vibe call: no well-known foci ($e)');
    }
    if (url == null) {
      for (final path in const [
        '/client/v1/rtc/transports',
        '/client/unstable/org.matrix.msc4143/rtc/transports',
      ]) {
        try {
          final r = await client.request(RequestType.GET, path);
          url = pick(r['rtc_transports']);
          if (url != null) break;
        } catch (_) {}
      }
    }
    _cache[key] = (DateTime.now(), url);
    return url;
  }

  static Future<bool> ensure(BuildContext context, Room room) async {
    final url = await serviceUrl(room.client);
    lastServiceUrl = url;
    if (url != null) return true;
    // Someone else's call brings its own call service: joining works.
    if (VibeCallMembers.active(room)) return true;
    if (!context.mounted) return false;
    final server = room.client.userID?.domain ?? 'your server';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Calls aren\'t set up on your server'),
        content: Text(
          '$server doesn\'t offer Matrix calls yet, so Vibe can\'t start '
          'one from this account.\n\n'
          'You can still join calls that others start (from servers like '
          'matrix.org). To start calls yourself, use an account on a '
          'server with calls, or ask your server\'s admin to add a '
          'MatrixRTC (LiveKit) call service.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }
}
