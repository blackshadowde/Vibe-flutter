// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Disappearing messages, per chat.
///
/// The timer is a `chat.vibe.disappearing` room state event, so both people
/// see the same setting. Only messages sent after it was turned on disappear.
/// - Every Vibe hides expired messages on screen right away.
/// - Each person's Vibe deletes (redacts) their OWN expired messages from
///   the server every few minutes while the app is running.
abstract class VibeDisappearing {
  static const type = 'chat.vibe.disappearing';

  static const options = <(Duration?, String)>[
    (null, 'Off'),
    (Duration(hours: 1), '1 hour'),
    (Duration(hours: 24), '24 hours'),
    (Duration(days: 7), '7 days'),
    (Duration(days: 90), '90 days'),
  ];

  static String label(Duration? d) {
    for (final o in options) {
      if (o.$1 == d) return o.$2;
    }
    if (d == null) return 'Off';
    if (d.inDays >= 1) return '${d.inDays} days';
    return '${d.inHours} hours';
  }

  /// Current timer of [room], or null when off.
  static ({Duration duration, int since})? of(Room room) {
    final c = room.getState(type)?.content;
    if (c == null) return null;
    final seconds = c['seconds'];
    final since = c['since'];
    if (seconds is! int || seconds <= 0 || since is! int) return null;
    return (duration: Duration(seconds: seconds), since: since);
  }

  static bool isExpired(Event e) {
    if (e.type != EventTypes.Message &&
        e.type != EventTypes.Encrypted &&
        e.type != EventTypes.Sticker) {
      return false;
    }
    final t = of(e.room);
    if (t == null) return false;
    final ts = e.originServerTs.millisecondsSinceEpoch;
    if (ts < t.since) return false;
    return DateTime.now().millisecondsSinceEpoch >
        ts + t.duration.inMilliseconds;
  }

  static Future<void> set(Room room, Duration? d) async {
    await room.client.setRoomStateWithKey(room.id, type, '', {
      'seconds': d?.inSeconds ?? 0,
      'since': DateTime.now().millisecondsSinceEpoch,
    });
    await room.sendEvent({
      'msgtype': MessageTypes.Notice,
      'body': d == null
          ? '⏱ Disappearing messages turned off'
          : '⏱ Disappearing messages on: new messages disappear after '
                '${label(d)}',
    });
  }

  /// "Disappearing messages" picker for the chat menu.
  static Future<void> pick(BuildContext context, Room room) async {
    final current = of(room)?.duration;
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<(Duration?, String)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Disappearing messages'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'New messages in this chat disappear for both of you after '
              'the time you pick. Older messages stay.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Row(
                children: [
                  Icon(
                    o.$1 == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(o.$2),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null || choice.$1 == current) return;
    try {
      await set(room, choice.$1);
      VibeHaptics.light();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            choice.$1 == null
                ? 'Disappearing messages off'
                : 'Messages now disappear after ${choice.$2}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not change it: $e')),
      );
    }
  }

  // ---------------- clean-up of my own expired messages ----------------

  static Timer? _timer;
  static bool _running = false;

  static void start(Client client) {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => sweep(client),
    );
    Future.delayed(const Duration(seconds: 30), () => sweep(client));
  }

  static Future<void> sweep(Client client) async {
    if (_running || !client.isLogged()) return;
    _running = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final room in client.rooms.toList()) {
        if (room.membership != Membership.join) continue;
        final t = of(room);
        if (t == null) continue;
        String? from;
        var redacted = 0;
        for (var page = 0; page < 3 && redacted < 20; page++) {
          final res = await client.getRoomEvents(
            room.id,
            Direction.b,
            from: from,
            limit: 100,
          );
          var reachedStart = false;
          for (final e in res.chunk) {
            final ts = e.originServerTs.millisecondsSinceEpoch;
            if (ts < t.since) {
              reachedStart = true;
              continue;
            }
            if (e.senderId != client.userID) continue;
            if (e.type != EventTypes.Message &&
                e.type != EventTypes.Encrypted &&
                e.type != EventTypes.Sticker) {
              continue;
            }
            if (e.content.isEmpty) continue; // already deleted
            if (now <= ts + t.duration.inMilliseconds) continue;
            try {
              await room.redactEvent(e.eventId, reason: 'Disappearing');
              redacted++;
              if (redacted >= 20) break;
            } catch (err) {
              Logs().w('Vibe disappearing: redact failed', err);
            }
          }
          from = res.end;
          if (reachedStart || from == null || res.chunk.isEmpty) break;
        }
      }
    } catch (e) {
      Logs().w('Vibe disappearing sweep failed', e);
    } finally {
      _running = false;
    }
  }
}
