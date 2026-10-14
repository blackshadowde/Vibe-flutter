// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Who is in a room's call right now, read from MatrixRTC membership state
/// (the same events Element Call, Element X and Sable write).
abstract class VibeCallMembers {
  static const memberType = 'org.matrix.msc3401.call.member';

  /// Room type of a "voice channel" (Sable / Element call rooms).
  static const voiceRoomType = 'org.matrix.msc3417.call';

  static const _defaultExpiry = Duration(hours: 4);

  static bool isVoiceRoom(Room room) =>
      room.getState(EventTypes.RoomCreate)?.content['type'] == voiceRoomType;

  /// User IDs with an active (not expired) call membership, oldest first.
  static List<String> userIds(Room room) {
    final states = room.states[memberType];
    if (states == null || states.isEmpty) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final seen = <String>{};
    final out = <String>[];
    for (final s in states.values) {
      final c = s.content;
      if (c.isEmpty) continue;
      final sent = s is Event ? s.originServerTs.millisecondsSinceEpoch : now;
      var active = false;
      final legacy = c['memberships'];
      if (legacy is List) {
        // older format: a list of memberships with their own expiry
        for (final m in legacy) {
          if (m is! Map) continue;
          final ts = m['expires_ts'];
          final exp = m['expires'];
          if (ts is int && ts > now) active = true;
          if (exp is int && sent + exp > now) active = true;
        }
      } else if (c['application'] == 'm.call' ||
          c.containsKey('focus_active')) {
        final created = c['created_ts'] is int ? c['created_ts'] as int : sent;
        final exp = c['expires'] is int
            ? c['expires'] as int
            : _defaultExpiry.inMilliseconds;
        active = created + exp > now;
      }
      if (!active) continue;
      final user = s.senderId;
      if (seen.add(user)) out.add(user);
    }
    return out;
  }

  static bool active(Room room) => userIds(room).isNotEmpty;

  /// Everyone's current call membership (one per device), oldest first —
  /// the order MatrixRTC uses to pick the call server ("oldest_membership").
  static List<VibeRtcMember> sessions(Room room) {
    final states = room.states[memberType];
    if (states == null || states.isEmpty) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <VibeRtcMember>[];
    for (final entry in states.entries) {
      final s = entry.value;
      final c = s.content;
      if (c.isEmpty || c['application'] != 'm.call') continue;
      if ((c['call_id'] ?? '') != '') continue;
      final device = c['device_id'];
      if (device is! String || device.isEmpty) continue;
      final sent = s is Event ? s.originServerTs.millisecondsSinceEpoch : now;
      final created = c['created_ts'] is int ? c['created_ts'] as int : sent;
      final exp = c['expires'] is int
          ? c['expires'] as int
          : _defaultExpiry.inMilliseconds;
      if (created + exp <= now) continue;
      out.add(
        VibeRtcMember(
          userId: s.senderId,
          deviceId: device,
          createdTs: created,
          eventId: s is Event ? s.eventId : null,
          stateKey: entry.key,
          content: c,
        ),
      );
    }
    out.sort((a, b) => a.createdTs.compareTo(b.createdTs));
    return out;
  }

  /// Ring notifications Element Call sends when starting a DM call.
  static const ringTypes = {
    'org.matrix.msc4075.rtc.notification',
    'org.matrix.msc4075.call.notify',
    'm.rtc.notification',
    'm.call.notify',
  };

  static const declineType = 'org.matrix.msc4310.rtc.decline';

  static bool isRing(Event e) {
    if (!ringTypes.contains(e.type)) return false;
    final kind = e.content['notification_type'] ?? e.content['notify_type'];
    return kind == 'ring';
  }

  /// How long a ring lasts (default 30 s).
  static Duration ringLifetime(Event e) {
    final l = e.content['lifetime'];
    return Duration(milliseconds: l is int && l > 0 && l < 120000 ? l : 30000);
  }

  /// When the ring started (sender_ts if given, else server time).
  static DateTime ringStart(Event e) {
    final ts = e.content['sender_ts'];
    return ts is int
        ? DateTime.fromMillisecondsSinceEpoch(ts)
        : e.originServerTs;
  }

  /// Does this ring want video?
  static bool ringVideo(Event e) {
    final intent = e.content['m.call.intent'] ?? e.content['call_intent'];
    return intent == 'video';
  }
}

/// One device's MatrixRTC call membership.
class VibeRtcMember {
  final String userId;
  final String deviceId;
  final int createdTs;
  final String? eventId;
  final String stateKey;
  final Map<String, Object?> content;

  const VibeRtcMember({
    required this.userId,
    required this.deviceId,
    required this.createdTs,
    required this.eventId,
    required this.stateKey,
    required this.content,
  });

  /// The LiveKit participant identity (and encryption key owner).
  String get participantId => '$userId:$deviceId';

  /// The call server this member prefers (the first LiveKit focus).
  ({String url, String alias})? get focus {
    final list = content['foci_preferred'];
    if (list is! List) return null;
    for (final f in list) {
      if (f is! Map || f['type'] != 'livekit') continue;
      final url = f['livekit_service_url'];
      final alias = f['livekit_alias'];
      if (url is String && url.isNotEmpty) {
        return (url: url, alias: alias is String ? alias : '');
      }
    }
    return null;
  }

  String? get intent => content['m.call.intent'] as String?;
}
