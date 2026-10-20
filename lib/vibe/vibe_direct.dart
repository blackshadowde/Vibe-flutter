// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_ntfy.dart';
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

  /// Starts the always-on service and listens to every signed-in account.
  /// [onEvent] shows the notification (Vibe's normal notification code).
  static Future<void> start(
    List<Client> clients,
    void Function(Client client, Event event) onEvent,
  ) async {
    await VibeNtfy.keepAlive();
    for (final client in clients) {
      if (!client.isLogged()) continue;
      // Keep syncing while Vibe is in the background (see MatrixState).
      client.backgroundSync = true;
      _subs[client.clientName] ??= client.onNotification.stream.listen(
        (event) => onEvent(client, event),
      );
    }
    // Stock Android (Pixel) cuts the network of apps that may be "optimised"
    // when the phone sleeps, so the connection silently stops. Ask until
    // Vibe is allowed, at most every 3 days.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - AppSettings.vibeBatteryAskedAt.value > 3 * 24 * 3600 * 1000 &&
        !await VibeNtfy.backgroundAllowed()) {
      await AppSettings.vibeBatteryAskedAt.setItem(now);
      await VibeNtfy.askBatteryExemption();
    }
  }

  static Future<void> stop() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    await VibeNtfy.releaseKeepAlive();
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
