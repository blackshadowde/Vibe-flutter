// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'dart:convert';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_set_status.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Custom status ("⚓ On watch · until 4:00 PM") + the person's time zone
/// ("2:14 AM for Ashish").
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

  /// When the status was last changed (ms). The newest one wins when you
  /// use Vibe on more than one device.
  final int updatedMs;

  /// What they're doing right now, shown as a card on their profile
  /// (e.g. listening: app, title, artist, cover, start, duration).
  final Map<String, Object?>? activity;

  const VibeStatus({
    this.emoji = '',
    this.text = '',
    this.untilMs,
    this.tzOffsetMin,
    this.tzName,
    this.updatedMs = 0,
    this.activity,
  });

  factory VibeStatus.fromContent(Map<String, Object?> c) => VibeStatus(
    emoji: c['emoji'] is String ? c['emoji'] as String : '',
    text: c['text'] is String ? c['text'] as String : '',
    untilMs: c['until'] is int ? c['until'] as int : null,
    tzOffsetMin: c['tz_offset'] is int ? c['tz_offset'] as int : null,
    tzName: c['tz_name'] is String ? c['tz_name'] as String : null,
    updatedMs: c['updated'] is int ? c['updated'] as int : 0,
    activity: c['activity'] is Map
        ? Map<String, Object?>.from(c['activity'] as Map)
        : null,
  );

  Map<String, Object?> toContent() => {
    'emoji': emoji,
    'text': text,
    if (untilMs != null) 'until': untilMs,
    if (tzOffsetMin != null) 'tz_offset': tzOffsetMin,
    if (tzName != null) 'tz_name': tzName,
    if (updatedMs > 0) 'updated': updatedMs,
    if (activity != null) 'activity': activity,
  };

  /// Same status (ignoring the time zone, which every device adds itself).
  bool sameAs(VibeStatus o) =>
      emoji == o.emoji &&
      text == o.text &&
      untilMs == o.untilMs &&
      updatedMs == o.updatedMs;

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

  static VibeStatus? _saved() {
    final saved = AppSettings.vibeMyStatus.value;
    if (saved.isEmpty) return null;
    try {
      final c = jsonDecode(saved);
      if (c is Map) return VibeStatus.fromContent(Map<String, Object?>.from(c));
    } catch (_) {}
    return null;
  }

  /// Newest copy of my status found in my direct chats (set from any of my
  /// devices), or null.
  static VibeStatus? _newestInChats(Client client) {
    VibeStatus? best;
    for (final r in client.rooms) {
      if (!r.isDirectChat || r.membership != Membership.join) continue;
      final c = r.getState(type, client.userID!)?.content;
      if (c == null || c['hidden'] == true) continue;
      final s = VibeStatus.fromContent(c);
      if (best == null || s.updatedMs > best.updatedMs) best = s;
    }
    return best;
  }

  /// My status: the newest of the copy on this phone (kept so it survives
  /// hiding it from people) and what my other devices set.
  static VibeStatus? mine(Client client) {
    final saved = _saved();
    final chats = _newestInChats(client);
    if (saved == null) return chats;
    if (chats != null && chats.updatedMs > saved.updatedMs) return chats;
    return saved;
  }

  /// Status privacy: may the person in direct chat [room] see my status and
  /// local time? (Settings > Security & sign-in > Status & local time.)
  static bool visibleIn(Room room) {
    switch (AppSettings.vibeStatusAudience.value) {
      case 'nobody':
        return false;
      case 'picked':
        final other = room.directChatMatrixID;
        if (other == null) return false;
        return AppSettings.vibeStatusAllowed.value.split(',').contains(other);
      default:
        return true;
    }
  }

  /// What a person who may not see my status gets: nothing, not even my time.
  static const Map<String, Object?> _hiddenContent = {
    'emoji': '',
    'text': '',
    'hidden': true,
  };

  static VibeStatus _withMyZone(VibeStatus s) {
    final now = DateTime.now();
    return VibeStatus(
      emoji: s.emoji,
      text: s.text,
      untilMs: s.untilMs,
      tzOffsetMin: now.timeZoneOffset.inMinutes,
      tzName: now.timeZoneName,
      updatedMs: s.updatedMs,
      activity: s.activity,
    );
  }

  /// Writes my status (or the hidden placeholder) into one chat.
  static Future<bool> _write(
    Client client,
    Room r,
    Map<String, Object?> content,
  ) async {
    try {
      await client.setRoomStateWithKey(
        r.id,
        type,
        client.userID!,
        visibleIn(r) ? content : _hiddenContent,
      );
      _failed.remove(r.id);
      return true;
    } catch (e) {
      // Usually: not allowed to change this chat's settings.
      _failed.add(r.id);
      Logs().d('Vibe status: could not set in ${r.id}', e);
      return false;
    }
  }

  /// Chats where writing failed; tried again only every few hours.
  static final Set<String> _failed = {};
  static DateTime _failedSince = DateTime.now();

  /// Runs [jobs] a few at a time, so a phone with many chats is quick
  /// without hitting the server's rate limit.
  static Future<int> _inBatches(List<Future<bool> Function()> jobs) async {
    var ok = 0;
    for (var i = 0; i < jobs.length; i += 4) {
      final results = await Future.wait(
        jobs.skip(i).take(4).map((j) => j()),
      );
      ok += results.where((r) => r).length;
    }
    return ok;
  }

  /// Save [s] to every direct chat. Returns in how many chats it was set.
  static Future<int> publish(Client client, VibeStatus s) async {
    final stamped = VibeStatus(
      emoji: s.emoji,
      text: s.text,
      untilMs: s.untilMs,
      updatedMs: DateTime.now().millisecondsSinceEpoch,
      activity: s.activity,
    );
    await AppSettings.vibeMyStatus.setItem(jsonEncode(stamped.toContent()));
    final content = _withMyZone(stamped).toContent();
    _failed.clear();
    final rooms = client.rooms
        .where((r) => r.isDirectChat && r.membership == Membership.join)
        .toList();
    return _inBatches([for (final r in rooms) () => _write(client, r, content)]);
  }

  static StreamSubscription? _watchSub;
  static Timer? _watchTimer;
  static Timer? _debounce;
  static Client? _watched;
  static Set<String> _knownDms = {};
  static int _knownZone = 0;
  static bool _running = false;

  static Set<String> _dms(Client c) => {
    for (final r in c.rooms)
      if (r.isDirectChat && r.membership == Membership.join) r.id,
  };

  /// Keeps my time zone (and status) present in every direct chat while
  /// Vibe runs: soon after start, whenever a new direct chat appears (new
  /// contact, accepted invite), when the phone's time zone changes, and
  /// every 30 minutes as a safety net.
  static void watch(Client client) {
    if (identical(_watched, client)) return;
    _watchSub?.cancel();
    _watchTimer?.cancel();
    _watched = client;
    _knownDms = {};
    _knownZone = DateTime.now().timeZoneOffset.inMinutes;
    _schedule(client, const Duration(seconds: 20));
    _watchSub = client.onSync.stream.listen((u) {
      final zone = DateTime.now().timeZoneOffset.inMinutes;
      final joined = u.rooms?.join?.keys ?? const <String>[];
      final changed =
          zone != _knownZone ||
          joined.any((id) => !_knownDms.contains(id)) ||
          (u.accountData?.any((e) => e.type == 'm.direct') ?? false);
      if (!changed) return;
      final now = _dms(client);
      if (zone != _knownZone || !now.every(_knownDms.contains)) {
        _schedule(client, const Duration(seconds: 5));
      }
    });
    _watchTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _schedule(client, Duration.zero),
    );
  }

  static void _schedule(Client client, Duration wait) {
    _debounce?.cancel();
    _debounce = Timer(wait, () async {
      if (_running || !client.isLogged()) return;
      _running = true;
      try {
        await refresh(client);
        _knownDms = _dms(client);
        _knownZone = DateTime.now().timeZoneOffset.inMinutes;
      } catch (e) {
        Logs().d('Vibe status refresh failed', e);
      } finally {
        _running = false;
      }
    });
  }

  /// Keep the time zone current and add the status to new direct chats.
  /// Cheap: only writes where something is missing or out of date.
  static Future<void> refresh(Client client) async {
    if (!client.isLogged()) return;
    // A newer status from another of my devices becomes this phone's too.
    final saved = _saved();
    final fromChats = _newestInChats(client);
    if (fromChats != null &&
        (saved == null || fromChats.updatedMs > saved.updatedMs)) {
      await AppSettings.vibeMyStatus.setItem(
        jsonEncode(
          VibeStatus(
            emoji: fromChats.emoji,
            text: fromChats.text,
            untilMs: fromChats.untilMs,
            updatedMs: fromChats.updatedMs,
            activity: fromChats.activity,
          ).toContent(),
        ),
      );
    }
    final current = mine(client) ?? const VibeStatus();
    final zone = DateTime.now().timeZoneOffset.inMinutes;
    final content = _withMyZone(current).toContent();
    if (DateTime.now().difference(_failedSince).inHours >= 6) {
      _failed.clear();
      _failedSince = DateTime.now();
    }
    final jobs = <Future<bool> Function()>[];
    for (final r in client.rooms.toList()) {
      if (!r.isDirectChat || r.membership != Membership.join) continue;
      if (_failed.contains(r.id)) continue;
      final had = r.getState(type, client.userID!)?.content;
      if (!visibleIn(r)) {
        if (had != null && had['hidden'] == true) continue;
      } else if (had != null && had['hidden'] != true) {
        final s = VibeStatus.fromContent(had);
        if (s.tzOffsetMin == zone && s.sameAs(current)) continue;
      }
      jobs.add(() => _write(client, r, content));
    }
    await _inBatches(jobs);
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

/// "🎧 Busy · until 4:00 PM" and/or "2:14 AM there" for [userId] in
/// [room]. Rebuilds on room updates and every minute (expiry, clock).
class VibeStatusLine extends StatefulWidget {
  final Room room;
  final String? userId;
  final bool showTime;

  /// Also show their time when it's the same as yours ("same time as you").
  final bool alwaysTime;
  final TextStyle? style;
  final String? fallback;
  final int maxLines;
  const VibeStatusLine({
    required this.room,
    required this.userId,
    this.showTime = true,
    this.alwaysTime = false,
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
    if (widget.showTime &&
        theirZone != null &&
        (theirZone != myZone || widget.alwaysTime)) {
      final t = DateTime.now().toUtc().add(Duration(minutes: theirZone));
      final clock = MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay(hour: t.hour, minute: t.minute));
      parts.add(
        theirZone == myZone
            ? '$clock · same time as you'
            : '$clock there',
      );
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

/// Opens the "Set your status" page (kept for existing callers).
abstract class VibeStatusSheet {
  static Future<void> show(BuildContext context, Client client) =>
      VibeSetStatusPage.open(context, client);
}

/// Discord-style thought bubble under the chat header: custom status (if
/// any) and the other person's local time. Tap to fold it away.
/// "6:42 PM there": the other person's local time, small, under their name
/// in the chat's top bar (where "Connecting to server…" shows while
/// connecting). Nothing if they don't share a time zone.
class VibeTheirTime extends StatefulWidget {
  final Room room;
  final String userId;
  final TextStyle? style;
  const VibeTheirTime({
    required this.room,
    required this.userId,
    this.style,
    super.key,
  });

  @override
  State<VibeTheirTime> createState() => _VibeTheirTimeState();
}

class _VibeTheirTimeState extends State<VibeTheirTime> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // on the minute, so the clock never lags
    final now = DateTime.now();
    _tick = Timer(Duration(seconds: 60 - now.second), () {
      if (mounted) setState(() {});
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zone = VibeStatus.of(widget.room, widget.userId)?.tzOffsetMin;
    if (zone == null) return const SizedBox.shrink();
    final t = DateTime.now().toUtc().add(Duration(minutes: zone));
    final clock = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay(hour: t.hour, minute: t.minute));
    final mine = DateTime.now().timeZoneOffset.inMinutes == zone;
    return Text(
      mine ? '$clock · same time as you' : '$clock there',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          widget.style ??
          TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class VibeStatusBubble extends StatefulWidget {
  final Room room;
  final String? userId;
  const VibeStatusBubble({required this.room, required this.userId, super.key});

  @override
  State<VibeStatusBubble> createState() => _VibeStatusBubbleState();
}

class _VibeStatusBubbleState extends State<VibeStatusBubble> {
  static final Set<String> _folded = {};
  Timer? _tick;
  StreamSubscription? _sub;

  bool get _isFolded => _folded.contains(widget.room.id);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
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

  void _toggle() {
    VibeHaptics.selection();
    setState(() {
      if (!_folded.remove(widget.room.id)) _folded.add(widget.room.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = VibeStatus.of(widget.room, widget.userId);
    String? statusText;
    if (s != null && s.active) {
      final until = s.until;
      statusText =
          '${s.emoji.isEmpty ? '' : '${s.emoji} '}${s.text}'
          '${until == null ? '' : ' · ${vibeUntil(context, until)}'}';
    }
    // The bubble is only for a custom status; their time sits under the
    // name in the top bar (VibeTheirTime).
    if (statusText == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final fill = cs.surfaceContainerHigh;
    final edge = Colors.white.withValues(alpha: 0.08);
    Widget dot(double d) => Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: edge),
      ),
    );

    final bubble = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: Container(
        padding: _isFolded
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 120,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: edge),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: _isFolded
            ? Text(
                s != null && s.active && s.emoji.isNotEmpty ? s.emoji : '💭',
                style: const TextStyle(fontSize: 14),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.85 + 0.15 * v,
          alignment: Alignment.topLeft,
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: _toggle,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 0, top: 0, child: dot(7)),
            Positioned(left: 6, top: 6, child: dot(11)),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 13),
              child: bubble,
            ),
          ],
        ),
      ),
    );
  }
}
