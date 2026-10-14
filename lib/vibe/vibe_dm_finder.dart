// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Finding (or starting) your one-to-one chat with someone.
///
/// The Matrix SDK only looks at the account's `m.direct` list. Chats made by
/// other apps (Element calls, invites) are often missing from it, and then a
/// second, sometimes unencrypted, chat with the same person was created.
/// Vibe looks for any existing two-person chat first and always encrypts
/// new ones.
abstract class VibeDmFinder {
  static Room? find(Client client, String userId, {String? currentRoomId}) {
    bool withThem(Room r) {
      if (r.membership != Membership.join && r.membership != Membership.invite) {
        return false;
      }
      if (r.isSpace) return false;
      if (r.directChatMatrixID == userId) return true;
      final count =
          (r.summary.mJoinedMemberCount ?? 0) +
          (r.summary.mInvitedMemberCount ?? 0);
      if (count > 2) return false;
      final m = r.getState(EventTypes.RoomMember, userId)?.content['membership'];
      final hero = r.summary.mHeroes?.contains(userId) ?? false;
      // a named group that just happens to have two people isn't a DM
      final named =
          (r.getState(EventTypes.RoomName)?.content['name'] as String?)
              ?.isNotEmpty ??
          false;
      return (m == 'join' || m == 'invite' || hero) && !named;
    }

    if (currentRoomId != null) {
      final cur = client.getRoomById(currentRoomId);
      if (cur != null && withThem(cur)) return cur;
    }
    final id = client.getDirectChatFromUserId(userId);
    final known = id == null ? null : client.getRoomById(id);
    if (known != null) return known;
    final rooms = client.rooms.where(withThem).toList()
      // prefer encrypted, then the most recently active
      ..sort((a, b) {
        if (a.encrypted != b.encrypted) return a.encrypted ? -1 : 1;
        return b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime);
      });
    return rooms.isEmpty ? null : rooms.first;
  }

  /// The chat's room ID, creating an encrypted chat if there is none.
  static Future<String> open(
    Client client,
    String userId, {
    String? currentRoomId,
  }) async {
    final room = find(client, userId, currentRoomId: currentRoomId);
    if (room != null) {
      if (room.directChatMatrixID != userId) {
        try {
          await room.addToDirectChat(userId);
        } catch (e) {
          Logs().v('Vibe: could not mark chat as direct $e');
        }
      }
      return room.id;
    }
    return client.startDirectChat(userId, enableEncryption: true);
  }

  /// Leave and forget a chat ("Delete chat"). The other person keeps their
  /// copy; Matrix can't delete a chat for both sides.
  static Future<void> delete(Room room) async {
    if (room.membership != Membership.leave) {
      try {
        await room.leave();
      } on MatrixException catch (e) {
        // already gone on the server: just forget it
        if (e.errcode != 'M_FORBIDDEN' && e.errcode != 'M_NOT_FOUND') rethrow;
      }
    }
    try {
      await room.forget();
    } catch (e) {
      Logs().v('Vibe: forget failed $e');
    }
  }

  /// Older Vibe versions sometimes made a second, unencrypted chat with
  /// someone you already had an encrypted chat with (after a call). Those
  /// are removed again, but only when Vibe made it and nobody wrote in it.
  static Future<void> cleanupDuplicates(Client client) async {
    final me = client.userID;
    if (me == null) return;
    final byUser = <String, List<Room>>{};
    for (final r in client.rooms) {
      if (r.membership != Membership.join || r.isSpace) continue;
      final count =
          (r.summary.mJoinedMemberCount ?? 0) +
          (r.summary.mInvitedMemberCount ?? 0);
      if (count > 2) continue;
      final other =
          r.directChatMatrixID ??
          r.summary.mHeroes?.firstWhere((u) => u != me, orElse: () => '');
      if (other == null || other.isEmpty) continue;
      byUser.putIfAbsent(other, () => []).add(r);
    }
    for (final rooms in byUser.values) {
      if (rooms.length < 2 || !rooms.any((r) => r.encrypted)) continue;
      for (final r in rooms.where((r) => !r.encrypted)) {
        final named =
            (r.getState(EventTypes.RoomName)?.content['name'] as String?)
                ?.isNotEmpty ??
            false;
        if (named) continue;
        if (r.getState(EventTypes.RoomCreate)?.senderId != me) continue;
        try {
          final res = await client.getRoomEvents(r.id, Direction.b, limit: 50);
          final written = res.chunk.any(
            (e) =>
                e.type == EventTypes.Message ||
                e.type == EventTypes.Encrypted ||
                e.type == EventTypes.Sticker,
          );
          if (written) continue;
          Logs().i('Vibe: removing empty duplicate chat ${r.id}');
          await delete(r);
        } catch (e) {
          Logs().v('Vibe: duplicate check failed for ${r.id} $e');
        }
      }
    }
  }
}
