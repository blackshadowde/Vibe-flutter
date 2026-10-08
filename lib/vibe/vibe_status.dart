// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Custom status ("⚓ On watch · until 4:00 PM") + the person's time zone
/// ("🌙 2:14 AM for Ashish").
///
/// Stored as a `chat.vibe.status` state event (state key = your user id) in
/// each of your direct chats, so only people you chat with can see it.
class VibeStatus {
  static const type = 'chat.vibe.status';

  final String emoji;
  final String text;
  final int? untilMs; // null = don't clear
  final int? tzOffsetMin; // minutes from UTC when last updated
  final String? tzName;

  const VibeStatus({
    this.emoji = '',
    this.text = '',
    this.untilMs,
    this.tzOffsetMin,
    this.tzName,
  });

  factory VibeStatus.fromContent(Map<String, Object?> c) => VibeStatus(
    emoji: c['emoji'] is String ? c['emoji'] as String : '',
    text: c['text'] is String ? c['text'] as String : '',
    untilMs: c['until'] is int ? c['until'] as int : null,
    tzOffsetMin: c['tz_offset'] is int ? c['tz_offset'] as int : null,
    tzName: c['tz_name'] is String ? c['tz_name'] as String : null,
  );

  Map<String, Object?> toContent() => {
    'emoji': emoji,
    'text': text,
    if (untilMs != null) 'until': untilMs,
    if (tzOffsetMin != null) 'tz_offset': tzOffsetMin,
    if (tzName != null) 'tz_name': tzName,
  };

  bool get active =>
      text.trim().isNotEmpty &&
      (untilMs == null || DateTime.now().millisecondsSinceEpoch < untilMs!);

  DateTime? get until =>
      untilMs == null ? null : DateTime.fromMillisecondsSinceEpoch(untilMs!);

  /// Status of [userId] as seen in [room], or null.
  static VibeStatus? of(Room room, String? userId) {
    if (userId == null) return null;
    final c = room.getState(type, userId)?.content;
    if (c == null) return null;
    return VibeStatus.fromContent(c);
  }

  /// My status (from any direct chat that has it).
  static VibeStatus? mine(Client client) {
    for (final r in client.rooms) {
      if (!r.isDirectChat || r.membership != Membership.join) continue;
      final s = of(r, client.userID);
      if (s != null) return s;
    }
    return null;
  }

  static VibeStatus _withMyZone(VibeStatus s) {
    final now = DateTime.now();
    return VibeStatus(
      emoji: s.emoji,
      text: s.text,
      untilMs: s.untilMs,
      tzOffsetMin: now.timeZoneOffset.inMinutes,
      tzName: now.timeZoneName,
    );
  }

  /// Save [s] to every direct chat. Rooms where it can't be set are skipped.
  static Future<int> publish(Client client, VibeStatus s) async {
    final content = _withMyZone(s).toContent();
    var ok = 0;
    for (final r in client.rooms.toList()) {
      if (!r.isDirectChat || r.membership != Membership.join) continue;
      try {
        await client.setRoomStateWithKey(r.id, type, client.userID!, content);
        ok++;
      } catch (e) {
        Logs().d('Vibe status: could not set in ${r.id}', e);
      }
    }
    return ok;
  }

  /// Keep the time zone current and add the status to new direct chats.
  /// Cheap: only writes where something is missing or out of date.
  static Future<void> refresh(Client client) async {
    if (!client.isLogged()) return;
    final current = mine(client) ?? const VibeStatus();
    final zone = DateTime.now().timeZoneOffset.inMinutes;
    final content = _withMyZone(current).toContent();
    for (final r in client.rooms.toList()) {
      if (!r.isDirectChat || r.membership != Membership.join) continue;
      final s = of(r, client.userID);
      if (s != null && s.tzOffsetMin == zone && s.text == current.text) {
        continue;
      }
      try {
        await client.setRoomStateWithKey(r.id, type, client.userID!, content);
      } catch (_) {}
    }
  }
}

/// Small helpers for showing times.
String vibeClock(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(t));

String vibeUntil(BuildContext context, DateTime until) {
  final now = DateTime.now();
  final sameDay =
      until.year == now.year &&
      until.month == now.month &&
      until.day == now.day;
  final clock = vibeClock(context, until);
  if (sameDay) return 'until $clock';
  if (until.difference(now).inDays < 6) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return 'until ${days[until.weekday - 1]} $clock';
  }
  return 'until ${until.day}/${until.month}';
}

/// "⚓ On watch · until 4:00 PM" and/or "🌙 2:14 AM there" for [userId] in
/// [room]. Rebuilds on room updates and every minute (expiry, clock).
class VibeStatusLine extends StatefulWidget {
  final Room room;
  final String? userId;
  final bool showTime;
  final TextStyle? style;
  final String? fallback;
  final int maxLines;
  const VibeStatusLine({
    required this.room,
    required this.userId,
    this.showTime = true,
    this.style,
    this.fallback,
    this.maxLines = 1,
    super.key,
  });

  @override
  State<VibeStatusLine> createState() => _VibeStatusLineState();
}

class _VibeStatusLineState extends State<VibeStatusLine> {
  Timer? _tick;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _sub = widget.room.client.onSync.stream
        .where((u) => u.rooms?.join?.containsKey(widget.room.id) ?? false)
        .listen((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = VibeStatus.of(widget.room, widget.userId);
    final parts = <String>[];
    if (s != null && s.active) {
      final until = s.until;
      parts.add(
        '${s.emoji.isEmpty ? '' : '${s.emoji} '}${s.text}'
        '${until == null ? '' : ' · ${vibeUntil(context, until)}'}',
      );
    }
    final myZone = DateTime.now().timeZoneOffset.inMinutes;
    final theirZone = s?.tzOffsetMin;
    if (widget.showTime && theirZone != null && theirZone != myZone) {
      final t = DateTime.now().toUtc().add(Duration(minutes: theirZone));
      final night = t.hour < 6 || t.hour >= 21;
      final clock = MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay(hour: t.hour, minute: t.minute));
      parts.add('${night ? '🌙' : '☀️'} $clock there');
    }
    final text = parts.isEmpty ? widget.fallback : parts.join('  ·  ');
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style:
          widget.style ??
          TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// Bottom sheet to set / clear your status.
abstract class VibeStatusSheet {
  static const _presets = [
    ('⚓', 'On watch'),
    ('💼', 'Busy at work'),
    ('😴', 'Sleeping'),
    ('🌊', 'At sea, slow internet'),
    ('🏝️', 'In port'),
    ('📵', 'Can\'t talk right now'),
  ];

  static const _durations = [
    ('30 min', Duration(minutes: 30)),
    ('1 hour', Duration(hours: 1)),
    ('4 hours', Duration(hours: 4)),
    ('Today', null), // until midnight
    ('1 week', Duration(days: 7)),
    ('Don\'t clear', Duration.zero),
  ];

  static Future<void> show(BuildContext context, Client client) async {
    final current = VibeStatus.mine(client);
    final active = current != null && current.active;
    var emoji = active ? current.emoji : '⚓';
    final text = TextEditingController(text: active ? current.text : '');
    var durIndex = 2; // 4 hours
    var saving = false;
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final cs = Theme.of(ctx).colorScheme;
          Future<void> save({required bool clear}) async {
            setSheet(() => saving = true);
            int? until;
            if (!clear) {
              final d = _durations[durIndex].$2;
              final now = DateTime.now();
              if (d == null) {
                until = DateTime(
                  now.year,
                  now.month,
                  now.day + 1,
                ).millisecondsSinceEpoch;
              } else if (d != Duration.zero) {
                until = now.add(d).millisecondsSinceEpoch;
              }
            }
            final s = clear
                ? const VibeStatus()
                : VibeStatus(
                    emoji: emoji,
                    text: text.text.trim(),
                    untilMs: until,
                  );
            final n = await VibeStatus.publish(client, s);
            VibeHaptics.light();
            if (ctx.mounted) Navigator.pop(ctx);
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  clear
                      ? 'Status cleared'
                      : n == 0
                      ? 'Could not set status in any chat'
                      : 'Status set',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Set a status',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only people you chat with can see it.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: text,
                    maxLength: 60,
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      hintText: 'What\'s happening?',
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      counterText: '',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          emoji.isEmpty ? '💬' : emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _presets)
                        ActionChip(
                          avatar: Text(p.$1),
                          label: Text(p.$2),
                          onPressed: () => setSheet(() {
                            emoji = p.$1;
                            text.text = p.$2;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Clear after',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _durations.length; i++)
                        ChoiceChip(
                          label: Text(_durations[i].$1),
                          selected: durIndex == i,
                          onSelected: (_) => setSheet(() => durIndex = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (active)
                        TextButton(
                          onPressed: saving ? null : () => save(clear: true),
                          child: const Text('Clear status'),
                        ),
                      const Spacer(),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF5865F2),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: saving || text.text.trim().isEmpty
                            ? null
                            : () => save(clear: false),
                        child: Text(saving ? 'Saving…' : 'Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    text.dispose();
  }
}
