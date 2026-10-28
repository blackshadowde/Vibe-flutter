// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Strict encryption: the chat's message key is replaced every
/// [msgs] messages or every hour, instead of Matrix's default (every 100
/// messages or a week). A leaked key then unlocks at most a handful of
/// messages. It's the standard Matrix room setting, so Element and every
/// other app keep reading the chat.
abstract class VibeStrict {
  static const msgs = 10;
  static const ms = 60 * 60 * 1000;
  static const _algorithm = 'm.megolm.v1.aes-sha2';

  static Map<String, Object?> _content(bool on) => {
    'algorithm': _algorithm,
    'rotation_period_ms': on ? ms : 7 * 24 * ms,
    'rotation_period_msgs': on ? msgs : 100,
  };

  static bool isOn(Room room) {
    if (!room.encrypted) return false;
    final c = room.getState(EventTypes.Encryption)?.content;
    final n = c?['rotation_period_msgs'];
    return n is int && n <= msgs;
  }

  /// Anyone allowed to change the chat's settings (in a DM usually both of
  /// you, in a group its admins).
  static bool canChange(Room room) =>
      room.encrypted &&
      room.membership == Membership.join &&
      room.canChangeStateEvent(EventTypes.Encryption);

  static Future<void> set(Room room, bool on) async {
    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.Encryption,
      '',
      _content(on),
    );
    // start the next message on a fresh key right away
    try {
      await room.client.encryption?.keyManager.clearOrUseOutboundGroupSession(
        room.id,
        wipe: true,
      );
    } catch (_) {}
  }

  /// For new chats Vibe creates (when "Strict for my new chats" is on).
  static List<StateEvent>? initialState() =>
      AppSettings.vibeStrictNew.value
      ? [StateEvent(type: EventTypes.Encryption, content: _content(true))]
      : null;

  /// The one-time introduction after the update.
  static Future<void> maybeIntro(BuildContext context) async {
    if (AppSettings.vibeStrictIntro.value) return;
    await AppSettings.vibeStrictIntro.setItem(true);
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => const _StrictIntro(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: 1.04, end: 1.0).animate(
              CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The chat's lock; with strict encryption it rewires into a filled shield.
class VibeLockShield extends StatefulWidget {
  final bool strict;
  final Color color;
  final double size;
  const VibeLockShield({
    required this.strict,
    required this.color,
    this.size = 18,
    super.key,
  });

  @override
  State<VibeLockShield> createState() => _VibeLockShieldState();
}

class _VibeLockShieldState extends State<VibeLockShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    // opening a strict chat: watch the lock turn into the shield
    if (widget.strict) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(VibeLockShield old) {
    super.didUpdateWidget(old);
    if (old.strict != widget.strict) {
      widget.strict ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: CustomPaint(
      painter: _LockShieldPainter(
        CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic),
        widget.color,
      ),
    ),
  );
}

class _LockShieldPainter extends CustomPainter {
  final Animation<double> t;
  final Color color;
  _LockShieldPainter(this.t, this.color) : super(repaint: t);

  static const _n = 64;

  // Both outlines start at the top middle and run clockwise, so the
  // points pair up and the body flows into the shield.
  static final Path _body = Path()
    ..moveTo(12, 10)
    ..lineTo(17, 10)
    ..arcToPoint(const Offset(19, 12), radius: const Radius.circular(2))
    ..lineTo(19, 19)
    ..arcToPoint(const Offset(17, 21), radius: const Radius.circular(2))
    ..lineTo(7, 21)
    ..arcToPoint(const Offset(5, 19), radius: const Radius.circular(2))
    ..lineTo(5, 12)
    ..arcToPoint(const Offset(7, 10), radius: const Radius.circular(2))
    ..close();

  static final Path _shield = Path()
    ..moveTo(12, 2)
    ..lineTo(20, 5.2)
    ..lineTo(20, 11)
    ..cubicTo(20, 16, 16.6, 19.8, 12, 22)
    ..cubicTo(7.4, 19.8, 4, 16, 4, 11)
    ..lineTo(4, 5.2)
    ..close();

  static final Path _shackle = Path()
    ..moveTo(8, 10)
    ..lineTo(8, 7)
    ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
    ..lineTo(16, 10);

  static List<Offset> _sample(Path p) {
    final m = p.computeMetrics().first;
    return [
      for (var i = 0; i < _n; i++)
        m.getTangentForOffset(m.length * i / _n)!.position,
    ];
  }

  static final _a = _sample(_body);
  static final _b = _sample(_shield);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;

    // the shackle: its wire is pulled up into the shield's tip
    final s = (v / 0.6).clamp(0.0, 1.0);
    if (s < 1) {
      final m = _shackle.computeMetrics().first;
      final keep = m.length * (1 - s);
      final start = (m.length - keep) / 2;
      final wire = m.extractPath(start, start + keep);
      canvas.save();
      canvas.translate(0, -3 * s);
      canvas.drawPath(
        wire,
        Paint()
          ..color = color.withValues(alpha: 1 - s * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }

    // the body becomes the shield
    final b = Curves.easeInOutCubic.transform(((v - 0.15) / 0.85).clamp(0.0, 1.0));
    final path = Path()..addPolygon([
      for (var i = 0; i < _n; i++) Offset.lerp(_a[i], _b[i], b)!,
    ], true);

    // keyhole fades out, a soft highlight fades in on the shield
    final hole = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = Colors.black.withValues(alpha: 1 - b);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
    canvas.drawPath(path, fill);
    canvas.drawCircle(const Offset(12, 15), 1.6, hole);
    if (b > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(12, 5)
          ..lineTo(12, 19.2)
          ..cubicTo(8.8, 17.6, 6.8, 14.8, 6.8, 11.2)
          ..lineTo(6.8, 7)
          ..close(),
        Paint()
          ..blendMode = BlendMode.srcATop
          ..color = Colors.white.withValues(alpha: 0.22 * b),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LockShieldPainter old) =>
      old.color != color || old.t != t;
}

class _StrictIntro extends StatefulWidget {
  const _StrictIntro();

  @override
  State<_StrictIntro> createState() => _StrictIntroState();
}

class _StrictIntroState extends State<_StrictIntro>
    with SingleTickerProviderStateMixin {
  bool _shield = false;
  bool _forNew = AppSettings.vibeStrictNew.value;
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      VibeHaptics.medium();
      setState(() => _shield = true);
    });
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const green = Color(0xFF23A55A);
    Widget point(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: green, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  Center(
                    child: AnimatedBuilder(
                      animation: _glow,
                      builder: (context, child) {
                        final p = _shield
                            ? 0.5 + 0.5 * math.sin(_glow.value * 2 * math.pi)
                            : 0.0;
                        return Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: green.withValues(alpha: 0.10),
                            boxShadow: [
                              BoxShadow(
                                color: green.withValues(alpha: 0.18 + 0.2 * p),
                                blurRadius: 30 + 18 * p,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: Center(
                        child: VibeLockShield(
                          strict: _shield,
                          color: green,
                          size: 72,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'New in Vibe',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: green,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Strict encryption',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your chats were already end-to-end encrypted. '
                    'Strict encryption makes a leaked key worth almost nothing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  point(
                    Icons.autorenew,
                    'What it does',
                    'Every chat locks its messages with a key. Normally that key '
                        'stays the same for up to 100 messages or a week. With '
                        'strict encryption a fresh key takes over every '
                        '${VibeStrict.msgs} messages or every hour.',
                  ),
                  point(
                    Icons.shield_outlined,
                    'Why it matters',
                    'If one key ever leaked from a phone or a backup, it would '
                        'unlock only a few messages, not weeks of your chat. '
                        'Element and other Matrix apps can still read the chat.',
                  ),
                  point(
                    Icons.group_outlined,
                    'Who can turn it on',
                    'Anyone allowed to change the chat\'s settings: in a direct '
                        'chat that\'s usually both of you, in a group its admins. '
                        'It covers everyone in the chat.',
                  ),
                  point(
                    Icons.touch_app_outlined,
                    'Where',
                    'Open a chat, tap the lock at the top, then switch on '
                        'Strict encryption. When it\'s on, the lock becomes a '
                        'shield.',
                  ),
                  Material(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      title: const Text(
                        'Strict for my new chats',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Chats you start from now on begin with it switched on',
                      ),
                      value: _forNew,
                      onChanged: (v) {
                        AppSettings.vibeStrictNew.setItem(v);
                        setState(() => _forNew = v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
