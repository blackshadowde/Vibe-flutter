// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_ntfy.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

/// Notifications the Vibgram way: Vibe keeps its own connection to the
/// Matrix server open (a small always-on service keeps the app alive) and
/// shows a notification the moment a message arrives in that connection.
///
/// No push gateway, no ntfy, no Firebase in between, so nothing on the way
/// can delay or drop a message. Notifications for encrypted chats can show
/// the real text, because Vibe has already opened the message on the phone.
/// Firebase (when the build has it) stays registered as a backup wake-up.
abstract class VibeDirect {
  static bool get enabled => AppSettings.vibePushMode.value == 'direct';

  static final Map<String, StreamSubscription<Event>> _subs = {};
  static final Map<String, StreamSubscription<SyncUpdate>> _readSubs = {};

  /// Starts the always-on service and listens to every signed-in account.
  /// [onEvent] shows the notification (Vibe's normal notification code).
  static Future<void> start(
    List<Client> clients,
    void Function(Client client, Event event) onEvent, {
    bool headless = false,
  }) async {
    await VibeNtfy.keepAlive();
    for (final client in clients) {
      if (!client.isLogged()) continue;
      // Keep syncing while Vibe is in the background (see MatrixState).
      client.backgroundSync = true;
      _subs[client.clientName] ??= client.onNotification.stream.listen(
        (event) => onEvent(client, event),
      );
      // a chat read (here or on another device): its notification goes
      _readSubs[client.clientName] ??= client.onSync.stream.listen(
        (update) => _clearRead(client, update),
      );
    }
    // Stock Android (Pixel) cuts the network of apps that may be "optimised"
    // when the phone sleeps, so the connection silently stops. Ask until
    // Vibe is allowed, at most every 3 days.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!headless &&
        now - AppSettings.vibeBatteryAskedAt.value > 3 * 24 * 3600 * 1000 &&
        !await VibeNtfy.backgroundAllowed()) {
      await AppSettings.vibeBatteryAskedAt.setItem(now);
      await VibeNtfy.askBatteryExemption();
    }
  }

  static Future<void> stop() async {
    for (final sub in [..._subs.values, ..._readSubs.values]) {
      await sub.cancel();
    }
    _subs.clear();
    _readSubs.clear();
    await VibeNtfy.releaseKeepAlive();
  }

  /// Removes the notifications of chats that are read now.
  static Future<void> _clearRead(Client client, SyncUpdate update) async {
    final joined = update.rooms?.join;
    if (joined == null || joined.isEmpty) return;
    final plugin = FlutterLocalNotificationsPlugin();
    try {
      final active = await plugin.getActiveNotifications();
      if (active.isEmpty) return;
      var removed = false;
      for (final roomId in joined.keys) {
        final room = client.getRoomById(roomId);
        if (room == null || room.isUnreadOrInvited) continue;
        final id = '${client.clientName}_$roomId'.hashCode;
        if (active.any((n) => n.id == id)) {
          await plugin.cancel(id: id);
          removed = true;
        }
      }
      if (!removed) return;
      // no chat notifications left: the group summary goes too
      final left = (await plugin.getActiveNotifications()).where(
        (n) => n.groupKey == client.clientName && n.id != client.clientName.hashCode,
      );
      if (left.isEmpty) await plugin.cancel(id: client.clientName.hashCode);
    } catch (e) {
      Logs().v('[VibeDirect] could not clear read notifications', e);
    }
  }

  /// A push-style description of [event], so Vibe's normal notification
  /// code (pushHelper) can show it exactly like a pushed one.
  static PushNotification pushFor(Client client, Event event) =>
      PushNotification.fromJson({
        'event_id': event.eventId,
        'room_id': event.room.id,
        'counts': {'unread': event.room.notificationCount},
        'devices': [
          {
            'app_id': 'chat.vibe.direct',
            'pushkey': 'direct',
            'data': {'client_name': client.clientName},
          },
        ],
      });
}
