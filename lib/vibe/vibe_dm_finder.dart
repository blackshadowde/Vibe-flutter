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
}
