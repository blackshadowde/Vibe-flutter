// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/call/vibe_call_members.dart';
import 'package:matrix/matrix.dart';

/// Your MatrixRTC membership in a room's call, written exactly like
/// Element Call / Element X / Sable do (matrix-js-sdk MembershipManager):
///
/// 1. schedule a delayed "left" event (8 s) on the server,
/// 2. post the "joined" state (`org.matrix.msc3401.call.member`),
/// 3. keep pushing the delayed "left" back every 5 s while in the call.
///
/// If Vibe is killed or loses the network, the server sends the "left"
/// event by itself, so nobody sees a call that never ends.
class VibeRtcSession {
  final Room room;
  final List<Map<String, Object?>> fociPreferred;
  final String intent;
  final void Function(String) log;

  VibeRtcSession({
    required this.room,
    required this.fociPreferred,
    required this.intent,
    required this.log,
  });

  static const delayMs = 8000;
  static const restartEvery = Duration(seconds: 5);
  static const expiresMs = 4 * 60 * 60 * 1000;

  Client get client => room.client;

  String get stateKey {
    final key = '${client.userID}_${client.deviceID}_m.call';
    // Room versions with owned state keys use the key without "_".
    final v = room.getState(EventTypes.RoomCreate)?.content['room_version'];
    if (v is String && RegExp(r'^org\.matrix\.msc(3757|3779)\b').hasMatch(v)) {
      return key;
    }
    return '_$key';
  }

  String? _delayId;
  bool _delayedSupported = true;
  Timer? _restart;
  Timer? _expiry;
  int _iterations = 1;
  int? _createdTs;
  bool _joined = false;

  /// Event ID of your current membership (rings and reactions point at it).
  String? membershipEventId;

  bool get joined => _joined;

  Map<String, Object?> _content(int expires) => {
    'application': 'm.call',
    'call_id': '',
    'scope': 'm.room',
    'device_id': client.deviceID,
    'expires': expires,
    'focus_active': {'type': 'livekit', 'focus_selection': 'oldest_membership'},
    'foci_preferred': fociPreferred,
    'm.call.intent': intent,
    'created_ts': ?_createdTs,
  };

  static String _e(String s) => Uri.encodeComponent(s);

  Future<void> join() async {
    await _sendDelayedLeave();
    membershipEventId = await client.setRoomStateWithKey(
      room.id,
      VibeCallMembers.memberType,
      stateKey,
      _content(expiresMs),
    );
    _joined = true;
    _createdTs = DateTime.now().millisecondsSinceEpoch;
    log('membership sent ${membershipEventId ?? ''}');
    // Posting the state can cancel the delayed event: check right away.
    unawaited(_restartDelayed());
    _restart?.cancel();
    _restart = Timer.periodic(restartEvery, (_) => _restartDelayed());
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    _expiry = Timer(
      Duration(milliseconds: expiresMs * _iterations - 60000),
      () async {
        if (!_joined) return;
        _iterations++;
        try {
          await client.setRoomStateWithKey(
            room.id,
            VibeCallMembers.memberType,
            stateKey,
            _content(expiresMs * _iterations),
          );
        } catch (e) {
          log('membership refresh failed: $e');
        }
        _scheduleExpiry();
      },
    );
  }

  Future<void> _sendDelayedLeave() async {
    if (!_delayedSupported) return;
    try {
      final res = await client.request(
        RequestType.PUT,
        '/client/v3/rooms/${_e(room.id)}/state/'
        '${_e(VibeCallMembers.memberType)}/${_e(stateKey)}',
        data: <String, Object?>{},
        query: {'org.matrix.msc4140.delay': '$delayMs'},
      );
      final id = res['delay_id'];
      if (id is String) {
        _delayId = id;
      } else {
        // The server ignored the delay (it set the state right away).
        _delayedSupported = false;
        log('server has no delayed events');
      }
    } on MatrixException catch (e) {
      _delayedSupported = false;
      log('delayed events not available: ${e.errcode}');
    } catch (e) {
      log('delayed leave failed: $e');
    }
  }

  Future<void> _updateDelayed(String id, String action) async {
    try {
      await client.request(
        RequestType.POST,
        '/client/unstable/org.matrix.msc4140/delayed_events/${_e(id)}',
        data: {'action': action},
      );
    } on MatrixException catch (e) {
      if (e.errcode != 'M_UNRECOGNIZED') rethrow;
      await client.request(
        RequestType.POST,
        '/client/v1/delayed_events/${_e(id)}/${_e(action)}',
        data: <String, Object?>{},
      );
    }
  }

  bool _restarting = false;

  Future<void> _restartDelayed() async {
    if (!_joined || !_delayedSupported || _restarting) return;
    _restarting = true;
    try {
      final id = _delayId;
      if (id == null) {
        await _sendDelayedLeave();
      } else {
        await _updateDelayed(id, 'restart');
      }
    } on MatrixException catch (e) {
      if (e.errcode == 'M_NOT_FOUND') {
        // gone (cancelled by our own join, or the server restarted)
        _delayId = null;
        await _sendDelayedLeave();
      } else {
        log('delayed restart failed: ${e.errcode}');
      }
    } catch (e) {
      log('delayed restart failed: $e');
    } finally {
      _restarting = false;
    }
  }

  /// Leave the call on the server.
  Future<void> leave() async {
    final wasJoined = _joined;
    _joined = false;
    _restart?.cancel();
    _expiry?.cancel();
    final id = _delayId;
    _delayId = null;
    var done = false;
    if (id != null) {
      try {
        await _updateDelayed(id, 'send');
        done = true;
      } catch (e) {
        log('delayed leave send failed: $e');
      }
    }
    if (!done || wasJoined) {
      try {
        await client.setRoomStateWithKey(
          room.id,
          VibeCallMembers.memberType,
          stateKey,
          {},
        );
      } catch (e) {
        log('leave state failed: $e');
      }
    }
    membershipEventId = null;
    log('left the call');
  }

  /// Ring the other person (DMs) or notify the room (groups), like
  /// Element Call does when you're the first one in the call.
  Future<List<String>> notify({required bool ring}) async {
    final parent = membershipEventId;
    if (parent == null) return const [];
    final ids = <String>[];
    try {
      final id = await room.sendEvent(
        {
          'm.mentions': {'user_ids': <String>[], 'room': true},
          'notification_type': ring ? 'ring' : 'notification',
          'm.relates_to': {'event_id': parent, 'rel_type': 'm.reference'},
          'sender_ts': DateTime.now().millisecondsSinceEpoch,
          'lifetime': 30000,
          'm.call.intent': intent,
        },
        type: 'org.matrix.msc4075.rtc.notification',
        displayPendingEvent: false,
      );
      if (id != null) ids.add(id);
      // older clients still listen for this one
      final legacy = await room.sendEvent(
        {
          'application': 'm.call',
          'm.mentions': {'user_ids': <String>[], 'room': true},
          'notify_type': ring ? 'ring' : 'notify',
          'call_id': '',
        },
        type: 'org.matrix.msc4075.call.notify',
        displayPendingEvent: false,
      );
      if (legacy != null) ids.add(legacy);
    } catch (e) {
      log('ring failed: $e');
    }
    return ids;
  }
}
