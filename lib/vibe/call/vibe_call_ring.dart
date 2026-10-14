// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/call/vibe_call.dart';
import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';

/// An incoming call that is ringing right now.
class VibeRing {
  final Room room;
  final Event event;
  final bool video;
  const VibeRing(this.room, this.event, this.video);

  String get callerId => event.senderId;
}

/// Listens for ring notifications (what Element Call, Element X and Sable
/// send when you start a DM call) and shows the incoming call screen.
class VibeCallRing {
  VibeCallRing._();
  static final VibeCallRing instance = VibeCallRing._();

  final ValueNotifier<VibeRing?> ringing = ValueNotifier(null);

  Client? _client;
  StreamSubscription? _sub;
  Timer? _end;
  Timer? _watch;
  Timer? _buzz;
  AudioPlayer? _player;
  final Set<String> _handled = {};

  void attach(Client client) {
    if (_client == client) return;
    _client = client;
    _sub?.cancel();
    _sub = client.onTimelineEvent.stream.listen(_onEvent);
    // Clear call memberships an earlier run left behind (app killed
    // mid-call), once the first sync has brought the rooms' state.
    unawaited(() async {
      try {
        if (client.prevBatch == null) {
          await client.onSync.stream.first.timeout(const Duration(minutes: 1));
        }
        await Future<void>.delayed(const Duration(seconds: 5));
        if (_client == client) await VibeCall.cleanupStale(client);
      } catch (e) {
        Logs().v('Vibe call: cleanup skipped $e');
      }
    }());
  }

  void _onEvent(Event e) {
    final client = _client;
    if (client == null) return;
    if (e.type == VibeCallMembers.declineType) {
      // declined on another of your devices
      final rel = e.content.tryGetMap<String, Object?>('m.relates_to');
      if (e.senderId == client.userID &&
          rel?['event_id'] == ringing.value?.event.eventId) {
        stop();
      }
      return;
    }
    if (!VibeCallMembers.isRing(e)) return;
    if (e.senderId == client.userID) return;
    if (!_handled.add(e.eventId)) return;
    final room = e.room;
    if (room.membership != Membership.join) return;
    if (VibeCall.instance.isIn(room)) return;
    final start = VibeCallMembers.ringStart(e);
    final life = VibeCallMembers.ringLifetime(e);
    final left = start.add(life).difference(DateTime.now());
    if (left <= Duration.zero || left > const Duration(minutes: 2)) return;
    if (ringing.value != null || VibeCall.instance.active) return;
    _ring(VibeRing(room, e, VibeCallMembers.ringVideo(e)), left);
  }

  void _ring(VibeRing ring, Duration left) {
    ringing.value = ring;
    _end?.cancel();
    _end = Timer(left, stop);
    // Stop when the caller gives up, or you answered on another device.
    final started = DateTime.now();
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 1), (_) {
      final members = VibeCallMembers.userIds(ring.room);
      final me = ring.room.client.userID;
      if (members.contains(me) && !VibeCall.instance.isIn(ring.room)) {
        stop(); // picked up elsewhere
        return;
      }
      if (DateTime.now().difference(started) > const Duration(seconds: 4) &&
          !members.contains(ring.callerId)) {
        stop(); // they hung up
      }
    });
    _startSound();
  }

  Future<void> _startSound() async {
    try {
      final p = _player ??= AudioPlayer();
      await p.setAsset('assets/sounds/phone.ogg');
      await p.setLoopMode(LoopMode.one);
      unawaited(p.play());
    } catch (e) {
      Logs().v('Vibe ring: no sound $e');
    }
    _buzz?.cancel();
    HapticFeedback.heavyImpact();
    _buzz = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void stop() {
    _end?.cancel();
    _watch?.cancel();
    _buzz?.cancel();
    _player?.stop();
    ringing.value = null;
  }

  Future<void> accept(BuildContext context) async {
    final ring = ringing.value;
    if (ring == null) return;
    stop();
    await VibeCall.join(context, ring.room, video: ring.video);
  }

  Future<void> decline() async {
    final ring = ringing.value;
    if (ring == null) return;
    stop();
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 2),
        () => VibeCall.markCallRead(ring.room),
      ),
    );
    try {
      await ring.room.sendEvent(
        {
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': ring.event.eventId,
          },
        },
        type: VibeCallMembers.declineType,
        displayPendingEvent: false,
      );
    } catch (e) {
      Logs().w('Vibe ring: decline failed', e);
    }
  }
}
