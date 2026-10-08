// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_status.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class VibeScheduled {
  final String id;
  final String roomId;
  final String text;
  final int at; // ms since epoch
  const VibeScheduled(this.id, this.roomId, this.text, this.at);

  Map<String, Object?> toJson() => {
    'id': id,
    'room': roomId,
    'text': text,
    'at': at,
  };

  static VibeScheduled? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], room = j['room'], text = j['text'], at = j['at'];
    if (id is! String || room is! String || text is! String || at is! int) {
      return null;
    }
    return VibeScheduled(id, room, text, at);
  }

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(at);
}

/// "Send later": long-press the send button. Messages wait on this phone
/// and are sent at the chosen time (or as soon as Vibe runs again if the
/// phone was off / the app was closed at that moment).
abstract class VibeSendLater {
  static const _key = 'chat.vibe.scheduled';
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static Timer? _timer;
  static bool _sending = false;

  static List<VibeScheduled> all() {
    try {
      final raw = AppSettings.store.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map(VibeScheduled.fromJson)
          .whereType<VibeScheduled>()
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));
    } catch (_) {
      return [];
    }
  }

  static List<VibeScheduled> forRoom(String roomId) =>
      all().where((s) => s.roomId == roomId).toList();

  static Future<void> _save(List<VibeScheduled> list) async {
    await AppSettings.store.setString(
      _key,
      jsonEncode(list.map((s) => s.toJson()).toList()),
    );
    changes.value++;
  }

  static Future<void> add(String roomId, String text, DateTime at) async {
    final list = all()
      ..add(
        VibeScheduled(
          '${DateTime.now().microsecondsSinceEpoch}',
          roomId,
          text,
          at.millisecondsSinceEpoch,
        ),
      );
    await _save(list);
  }

  static Future<void> remove(String id) async =>
      _save(all()..removeWhere((s) => s.id == id));

  static void start(Client client) {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _sendDue(client),
    );
    Future.delayed(const Duration(seconds: 8), () => _sendDue(client));
  }

  static Future<void> sendNow(Client client, VibeScheduled s) async {
    final room = client.getRoomById(s.roomId);
    if (room == null) return;
    await remove(s.id);
    await room.sendTextEvent(s.text);
  }

  static Future<void> _sendDue(Client client) async {
    if (_sending || !client.isLogged()) return;
    _sending = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final s in all().where((s) => s.at <= now)) {
        final room = client.getRoomById(s.roomId);
        if (room == null) {
          // Chat left / other account: drop it.
          await remove(s.id);
          continue;
        }
        await remove(s.id);
        // ignore: unawaited_futures
        room.sendTextEvent(s.text);
      }
    } catch (e) {
      Logs().w('Vibe send later failed', e);
    } finally {
      _sending = false;
    }
  }

  static String when(BuildContext context, DateTime t) {
    final now = DateTime.now();
    final clock = vibeClock(context, t);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today, $clock';
    if (diff == 1) return 'Tomorrow, $clock';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (diff < 7) return '${days[t.weekday - 1]}, $clock';
    return '${t.day}/${t.month}, $clock';
  }

  /// Long-press on send.
  static Future<void> pick(BuildContext context, ChatController c) async {
    final text = c.sendController.text.trim();
    if (text.isEmpty) return;
    VibeHaptics.medium();
    final now = DateTime.now();
    final room = c.room;

    // Their 8 AM, if we know their time zone.
    DateTime? theirMorning;
    final zone = VibeStatus.of(room, room.directChatMatrixID)?.tzOffsetMin;
    if (zone != null && zone != now.timeZoneOffset.inMinutes) {
      final theirNow = now.toUtc().add(Duration(minutes: zone));
      var target = DateTime.utc(
        theirNow.year,
        theirNow.month,
        theirNow.day,
        8,
      );
      if (!target.isAfter(theirNow)) {
        target = target.add(const Duration(days: 1));
      }
      theirMorning = target.subtract(Duration(minutes: zone)).toLocal();
    }

    final tonight = DateTime(now.year, now.month, now.day, 21);
    final tomorrow8 = DateTime(now.year, now.month, now.day + 1, 8);
    final options = <(String, DateTime)>[
      ('In 1 hour', now.add(const Duration(hours: 1))),
      if (now.isBefore(tonight)) ('Tonight', tonight),
      ('Tomorrow morning', tomorrow8),
      if (theirMorning != null) ('Their morning (8 AM there)', theirMorning),
    ];

    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Send later',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '“${text.length > 60 ? '${text.substring(0, 60)}…' : text}”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            for (final o in options)
              ListTile(
                leading: const Icon(Icons.schedule_send_outlined),
                title: Text(o.$1),
                subtitle: Text(when(ctx, o.$2)),
                onTap: () => Navigator.pop(ctx, o.$2),
              ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Pick date & time'),
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || picked == null) return;
    DateTime? at = picked is DateTime ? picked : null;
    if (picked == 'custom') {
      final date = await showDatePicker(
        context: context,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 365)),
        initialDate: now,
      );
      if (date == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          now.add(const Duration(hours: 1)),
        ),
      );
      if (time == null || !context.mounted) return;
      at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (!at.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a time in the future')),
        );
        return;
      }
    }
    if (at == null) return;
    await add(room.id, text, at);
    c.sendController.clear();
    c.onInputBarChanged('');
    VibeHaptics.light();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🕓 Scheduled for ${when(context, at)}'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => showList(context, room),
        ),
      ),
    );
  }

  /// List of scheduled messages for [room] (chat ⋮ menu).
  static Future<void> showList(BuildContext context, Room room) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useRootNavigator: true,
        builder: (ctx) => SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: changes,
            builder: (ctx, _, _) {
              final list = forRoom(room.id);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Scheduled messages',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(
                        'Nothing scheduled. Long-press the send button to '
                        'send a message later.',
                      ),
                    ),
                  for (final s in list)
                    ListTile(
                      leading: const Icon(Icons.schedule_send_outlined),
                      title: Text(
                        s.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(when(ctx, s.time)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Send now',
                            icon: const Icon(Icons.send_rounded),
                            onPressed: () => sendNow(room.client, s),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => remove(s.id),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      );
}
