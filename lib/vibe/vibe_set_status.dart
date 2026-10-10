// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_profile_cache.dart';
import 'package:fluffychat/vibe/vibe_status.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

const _statusHint = 'What are you currently obsessed with?';
const _bannerColor = Color(0xFF1F2624);
const _onlineGreen = Color(0xFF23A55A);
const _blurple = Color(0xFF5865F2);

/// Discord-style thought bubble: two small dots trailing up-left to the
/// profile picture, then a rounded bubble. Shows the status, or
/// "+ What are you currently obsessed with?" when there is none.
class VibeThoughtBubble extends StatelessWidget {
  final String? text;
  final bool showPlus;
  final VoidCallback? onTap;
  const VibeThoughtBubble({this.text, this.showPlus = false, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF2B2D31) : Colors.white;
    final edge = dark ? const Color(0xFF3F4147) : const Color(0xFFDDDEE1);
    final ink = dark ? const Color(0xFFF2F3F5) : const Color(0xFF2E3035);
    final empty = text == null || text!.trim().isEmpty;

    Widget dot(double d) => Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: edge),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, top: 0, child: dot(12)),
          Positioned(left: 18, top: 10, child: dot(20)),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: edge),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (showPlus && empty)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: ink,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.add, size: 17, color: fill),
                          ),
                        ),
                      ),
                    TextSpan(text: empty ? _statusHint : text),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                  color: empty ? ink.withValues(alpha: 0.85) : ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round profile picture with a thick ring and the green online dot.
class VibeRingAvatar extends StatelessWidget {
  final Uri? mxc;
  final String name;
  final Client client;
  final double size;
  final Color ring;
  const VibeRingAvatar({
    required this.mxc,
    required this.name,
    required this.client,
    required this.ring,
    this.size = 104,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ringW = size * 0.06;
    return SizedBox(
      width: size + ringW * 2,
      height: size + ringW * 2,
      child: Stack(
        children: [
          Container(
            padding: EdgeInsets.all(ringW),
            decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
            child: Avatar(mxContent: mxc, name: name, size: size, client: client),
          ),
          Positioned(
            right: ringW * 0.6,
            bottom: ringW * 0.6,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                color: _onlineGreen,
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: ringW),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Set your status" page (Discord style): live preview card, status field
/// with emoji, and "Clear at".
class VibeSetStatusPage extends StatefulWidget {
  final Client client;
  const VibeSetStatusPage({required this.client, super.key});

  static Future<void> open(BuildContext context, Client client) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VibeSetStatusPage(client: client),
        ),
      );

  @override
  State<VibeSetStatusPage> createState() => _VibeSetStatusPageState();
}

enum _Clear { min30, hour1, hour4, today, tomorrow, week, never }

class _VibeSetStatusPageState extends State<VibeSetStatusPage> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  String _emoji = '';
  late DateTime? _clearAt; // null = don't clear
  bool _saving = false;
  bool _hadStatus = false;
  late Future<Profile> _profile;

  static const _emojis = [
    '😀', '😎', '🥳', '😴', '🤒', '🤔', '❤️', '🔥', '🎧', '🎮',
    '📚', '💼', '☕', '🍕', '✈️', '🚢', '⚓', '🌊', '🏖️', '🏝️',
    '🏃', '💪', '🎬', '🎉', '🙏', '📵', '🌙', '☀️', '🌧️', '🏠',
  ];

  @override
  void initState() {
    super.initState();
    _profile = VibeProfileCache.get(widget.client);
    final s = VibeStatus.mine(widget.client);
    if (s != null && s.active) {
      _hadStatus = true;
      _text.text = s.text;
      _emoji = s.emoji;
      _clearAt = s.until;
    } else {
      _clearAt = _resolve(_Clear.tomorrow);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime? _resolve(_Clear c) {
    final now = DateTime.now();
    switch (c) {
      case _Clear.min30:
        return now.add(const Duration(minutes: 30));
      case _Clear.hour1:
        return now.add(const Duration(hours: 1));
      case _Clear.hour4:
        return now.add(const Duration(hours: 4));
      case _Clear.today:
        return DateTime(now.year, now.month, now.day, 23, 59);
      case _Clear.tomorrow:
        return now.add(const Duration(days: 1));
      case _Clear.week:
        return now.add(const Duration(days: 7));
      case _Clear.never:
        return null;
    }
  }

  String _label(_Clear c) => switch (c) {
    _Clear.min30 => '30 minutes',
    _Clear.hour1 => '1 hour',
    _Clear.hour4 => '4 hours',
    _Clear.today => 'Today',
    _Clear.tomorrow => 'Tomorrow',
    _Clear.week => '1 week',
    _Clear.never => 'Don\'t clear',
  };

  String _clearText(BuildContext context) {
    final at = _clearAt;
    if (at == null) return 'Don\'t clear';
    final now = DateTime.now();
    final clock = vibeClock(context, at);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today at $clock';
    if (diff == 1) return 'Tomorrow at $clock';
    if (diff < 7) {
      const days = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
        'Saturday', 'Sunday',
      ];
      return '${days[at.weekday - 1]} at $clock';
    }
    return '${at.day}/${at.month} at $clock';
  }

  Future<void> _pickClear() async {
    final picked = await showModalBottomSheet<_Clear>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Clear after',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final c in _Clear.values)
              ListTile(
                title: Text(_label(c)),
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _clearAt = _resolve(picked));
    }
  }

  Future<void> _pickEmoji() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _emojis)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, e),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, ''),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.block, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _emoji = picked);
  }

  Future<void> _save({bool clear = false}) async {
    if (_saving) return;
    final text = _text.text.trim();
    final clearing = clear || text.isEmpty;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = clearing
        ? const VibeStatus()
        : VibeStatus(
            emoji: _emoji,
            text: text,
            untilMs: _clearAt?.millisecondsSinceEpoch,
          );
    final n = await VibeStatus.publish(widget.client, s);
    VibeHaptics.light();
    if (mounted) Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          clearing
              ? 'Status cleared'
              : n == 0
              ? 'Could not set status in any chat'
              : 'Status set',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF232428) : const Color(0xFFF2F3F5);
    final fieldColor = dark ? const Color(0xFF1E1F22) : const Color(0xFFEBEDEF);
    final canSave = _text.text.trim().isNotEmpty || _hadStatus;
    final userId = widget.client.userID ?? '';
    final preview = _text.text.trim().isEmpty
        ? null
        : (_emoji.isEmpty ? _text.text.trim() : '$_emoji ${_text.text.trim()}');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text(
          'Set your status',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: canSave && !_saving ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: canSave ? _blurple : _blurple.withValues(alpha: 0.5),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<Profile>(
        future: _profile,
        builder: (context, snap) {
          final p = snap.data;
          final name = (p?.displayName?.isNotEmpty ?? false)
              ? p!.displayName!
              : (userId.localpart ?? userId);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // Preview card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: dark ? const Color(0xFF2E3035) : const Color(0xFFE3E5E8),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 200,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(height: 110, color: _bannerColor),
                          Positioned(
                            left: 14,
                            top: 74,
                            child: VibeRingAvatar(
                              mxc: p?.avatarUrl,
                              name: name,
                              client: widget.client,
                              ring: cardColor,
                              size: 96,
                            ),
                          ),
                          Positioned(
                            left: 128,
                            right: 14,
                            top: 92,
                            child: VibeThoughtBubble(
                              text: preview,
                              onTap: () => _focus.requestFocus(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            userId.localpart ?? userId,
                            style: TextStyle(
                              fontSize: 15,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Status',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: fieldColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _pickEmoji,
                      icon: _emoji.isEmpty
                          ? Icon(
                              Icons.emoji_emotions,
                              color: cs.onSurfaceVariant,
                            )
                          : Text(_emoji, style: const TextStyle(fontSize: 22)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => canSave ? _save() : null,
                        decoration: const InputDecoration(
                          hintText: _statusHint,
                          border: InputBorder.none,
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(vertical: 18),
                        ),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    if (_text.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: () => setState(() {
                          _text.clear();
                          _emoji = '';
                        }),
                        icon: Icon(Icons.cancel, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: fieldColor,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _pickClear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Clear at', style: TextStyle(fontSize: 16)),
                        ),
                        Text(
                          _clearText(context),
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
              if (_hadStatus) ...[
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : () => _save(clear: true),
                    child: Text(
                      'Clear status',
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
