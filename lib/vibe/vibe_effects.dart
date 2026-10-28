// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:vibe/vibe/screens/chat/chat.dart';
import 'package:vibe/vibe/vibe_animated_emoji.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_low_data.dart';
import 'package:vibe/vibe/vibe_send_later.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart';

/// How the particles of an effect move.
enum VibeEmit {
  /// Out from the message in every direction.
  burst,

  /// Up from the bottom of the screen (hearts, fire, balloons).
  rise,

  /// Down from the top of the screen (rain of emoji).
  fall,

  /// Two cannons in the bottom corners (party).
  cannons,
}

enum _Kind { glyph, confetti, ember, spark, dot }

/// One "send with effect" option.
class VibeEffect {
  final String id;
  final String emoji;
  final String label;
  final VibeEmit emit;
  final List<String> glyphs;
  final List<Color> colors;
  final List<_Kind> kinds;
  final int count;
  const VibeEffect(
    this.id,
    this.emoji,
    this.label,
    this.emit, {
    required this.glyphs,
    required this.colors,
    required this.kinds,
    this.count = 36,
  });
}

/// Send with effects (long-press the send button): the message arrives with
/// a full-screen animation for you and for everyone on Vibe. Other Matrix
/// apps just see the text.
///
/// The animations are Vibe's own; the big emoji is Google's Noto Animated
/// Emoji. (Telegram's effects are files on Telegram's servers, not in its
/// open-source app, so they can't be reused.)
abstract class VibeEffects {
  /// Content key on the message: `"chat.vibe.effect": "<id>"`.
  static const contentKey = 'chat.vibe.effect';

  static const List<VibeEffect> all = [
    VibeEffect(
      'like',
      '👍',
      'Like',
      VibeEmit.burst,
      glyphs: ['👍', '👍', '✨'],
      colors: [Color(0xFFFFD54F), Color(0xFFFFB74D), Color(0xFF8C96F6)],
      kinds: [_Kind.glyph, _Kind.glyph, _Kind.spark, _Kind.dot],
    ),
    VibeEffect(
      'love',
      '❤️',
      'Love',
      VibeEmit.rise,
      glyphs: ['❤️', '💕', '💖', '💗'],
      colors: [Color(0xFFFF5A5F), Color(0xFFFF80AB), Color(0xFFFFC1E3)],
      kinds: [_Kind.glyph, _Kind.glyph, _Kind.glyph, _Kind.dot],
      count: 30,
    ),
    VibeEffect(
      'fire',
      '🔥',
      'Fire',
      VibeEmit.rise,
      glyphs: ['🔥'],
      colors: [Color(0xFFFF7043), Color(0xFFFFB300), Color(0xFFFF3D00)],
      kinds: [_Kind.ember, _Kind.ember, _Kind.ember, _Kind.glyph],
      count: 48,
    ),
    VibeEffect(
      'party',
      '🎉',
      'Party',
      VibeEmit.cannons,
      glyphs: ['🎉', '🎊'],
      colors: [
        Color(0xFFFF5252),
        Color(0xFFFFD740),
        Color(0xFF69F0AE),
        Color(0xFF40C4FF),
        Color(0xFFE040FB),
      ],
      kinds: [_Kind.confetti, _Kind.confetti, _Kind.confetti, _Kind.glyph],
      count: 70,
    ),
    VibeEffect(
      'lol',
      '😂',
      'LOL',
      VibeEmit.fall,
      glyphs: ['😂', '🤣'],
      colors: [Color(0xFF4FC3F7), Color(0xFFFFC83D)],
      kinds: [_Kind.glyph, _Kind.glyph, _Kind.dot],
      count: 30,
    ),
    VibeEffect(
      'dislike',
      '👎',
      'Dislike',
      VibeEmit.fall,
      glyphs: ['👎'],
      colors: [Color(0xFF90A4AE), Color(0xFFB0BEC5)],
      kinds: [_Kind.glyph, _Kind.glyph, _Kind.dot],
      count: 22,
    ),
    VibeEffect(
      'poop',
      '💩',
      'Poop',
      VibeEmit.fall,
      glyphs: ['💩'],
      colors: [Color(0xFF8D6E63), Color(0xFFA1887F)],
      kinds: [_Kind.glyph, _Kind.glyph, _Kind.dot],
      count: 24,
    ),
    VibeEffect(
      'balloons',
      '🎈',
      'Balloons',
      VibeEmit.rise,
      glyphs: ['🎈'],
      colors: [Color(0xFFFF5252), Color(0xFF40C4FF), Color(0xFFFFD740)],
      kinds: [_Kind.glyph],
      count: 20,
    ),
  ];

  static VibeEffect? byId(String? id) {
    if (id == null) return null;
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }

  static VibeEffect? of(Event event) =>
      byId(event.content.tryGet<String>(contentKey));

  /// Emoji-only messages tapped by the user: a burst made from that emoji.
  static VibeEffect forEmoji(String emoji) => VibeEffect(
    'emoji',
    emoji,
    '',
    VibeEmit.burst,
    glyphs: [emoji],
    colors: const [Color(0xFF8C96F6), Color(0xFFFFD54F), Color(0xFF80DEEA)],
    kinds: const [_Kind.glyph, _Kind.glyph, _Kind.spark, _Kind.dot],
    count: 26,
  );

  // ---- sending ----

  /// Same message [Room.sendTextEvent] would send (mentions, markdown), plus
  /// the effect.
  static Future<String?> send(
    Room room,
    String message,
    VibeEffect effect, {
    Event? inReplyTo,
    String? threadRootEventId,
  }) {
    final content = <String, dynamic>{
      'msgtype': MessageTypes.Text,
      'body': message,
      contentKey: effect.id,
    };
    var mentions =
        message
            .split('@')
            .map(
              (t) => t.startsWith('[')
                  ? '@${t.split(']').first}]'
                  : '@${t.split(RegExp(r'\s+')).first}',
            )
            .toList()
          ..removeAt(0);
    final roomMention = mentions.remove('@room');
    mentions =
        mentions
            .map((m) => m.isValidMatrixIdStrict() ? m : room.getMention(m))
            .nonNulls
            .toSet()
            .toList()
          ..remove(room.client.userID);
    if (inReplyTo != null) mentions.add(inReplyTo.senderId);
    if (roomMention || mentions.isNotEmpty) {
      content['m.mentions'] = {
        if (roomMention) 'room': true,
        if (mentions.isNotEmpty) 'user_ids': mentions,
      };
    }
    final html = markdown(
      message,
      getEmotePacks: () => room.getImagePacksFlat(ImagePackUsage.emoticon),
      getMention: room.getMention,
      convertLinebreaks: room.client.convertLinebreaksInFormatting,
      enableLatex: room.client.enableLatexMarkdown,
    );
    final plain = html
        .replaceAll(RegExp(r'<br />\n?'), '\n')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    if (plain != message) {
      content['format'] = 'org.matrix.custom.html';
      content['formatted_body'] = html;
    }
    return room.sendEvent(
      content,
      inReplyTo: inReplyTo,
      threadRootEventId: threadRootEventId,
    );
  }

  // ---- playing ----

  static final Set<String> _played = {};

  /// Called by every message as it appears. Plays a message's effect once:
  /// right away for your own, and for others' messages that just arrived.
  static void maybePlay(BuildContext context, Event event) {
    final effect = of(event);
    if (effect == null) return;
    final ids = {event.eventId, ?event.transactionId};
    if (ids.any(_played.contains)) return;
    _played.addAll(ids);
    final mine = event.senderId == event.room.client.userID;
    final fresh =
        DateTime.now().difference(event.originServerTs).inSeconds.abs() < 90;
    if (!mine && !fresh) return;
    if (mine && event.status.isSynced && !fresh) return;
    // Let the message slide into the timeline first (its entrance takes
    // ~460 ms), then play the effect, so the two never fight.
    Future<void>.delayed(_settle, () {
      if (context.mounted) play(context, effect);
    });
  }

  static const _settle = Duration(milliseconds: 520);

  /// Plays [effect] over the whole chat screen: everything between the top
  /// bar and the message box, above the keyboard. A tapped emoji bursts
  /// where it is; every other effect fills the screen from its middle.
  static void play(BuildContext context, VibeEffect effect) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    Offset? anchor;
    if (effect.id == 'emoji') {
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        anchor = box.localToGlobal(box.size.center(Offset.zero));
      }
    }
    VibeHaptics.medium();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _EffectPlayer(
        effect: effect,
        anchor: anchor,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  // ---- long-press on the send button ----

  static Future<void> showSendOptions(
    BuildContext context,
    ChatController controller,
  ) async {
    final text = controller.sendController.text.trim();
    if (text.isEmpty) return;
    VibeHaptics.medium();
    final choice = await showVibeSheet<Object>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _SendOptionsSheet(text: text),
    );
    if (!context.mounted || choice == null) return;
    if (choice is VibeEffect) {
      controller.sendEffect = choice;
      await controller.send();
      controller.sendEffect = null;
    } else if (choice == 'later') {
      await VibeSendLater.pick(context, controller);
    }
  }
}

class _SendOptionsSheet extends StatelessWidget {
  final String text;
  const _SendOptionsSheet({required this.text});

  @override
  Widget build(BuildContext context) {
    final card = VibeSettingsStyle.card(context);
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '“${text.length > 80 ? '${text.substring(0, 80)}…' : text}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t2, fontStyle: FontStyle.italic),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text(
              'Send with effect',
              style: TextStyle(color: t2, fontSize: 15),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.05,
              children: [
                for (final e in VibeEffects.all)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).pop(e),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        VibeAnimatedEmoji(e.emoji, size: 40),
                        const SizedBox(height: 6),
                        Text(e.label, style: TextStyle(fontSize: 12, color: t2)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(Icons.schedule_send_outlined, color: t1),
                title: Text('Send later', style: TextStyle(color: t1)),
                trailing: Icon(Icons.chevron_right, color: t2),
                onTap: () => Navigator.of(context).pop('later'),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Small effect emoji next to a message that was sent with one. Tap to
/// play it again.
class VibeEffectBadge extends StatelessWidget {
  final VibeEffect effect;
  const VibeEffectBadge(this.effect, {super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${effect.label} effect',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => VibeEffects.play(context, effect),
        // Bigger touch area than the little emoji itself.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 6, 4),
          child: Text(effect.emoji, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The animation: the big animated emoji pops up at the message, wobbles and
// fades, while particles fill the screen in the effect's own way.
// ---------------------------------------------------------------------------

class _Particle {
  final _Kind kind;
  final Offset start;
  final Offset velocity; // px per run
  final double size;
  final double delay; // 0..1
  final double life; // 0..1
  final double spin;
  final double sway;
  final Color color;
  final TextPainter? tp;
  const _Particle({
    required this.kind,
    required this.start,
    required this.velocity,
    required this.size,
    required this.delay,
    required this.life,
    required this.spin,
    required this.sway,
    required this.color,
    this.tp,
  });
}

class _EffectPlayer extends StatefulWidget {
  final VibeEffect effect;

  /// Where a tapped emoji bursts from; null = middle of the chat screen.
  final Offset? anchor;
  final VoidCallback onDone;
  const _EffectPlayer({
    required this.effect,
    required this.anchor,
    required this.onDone,
  });

  @override
  State<_EffectPlayer> createState() => _EffectPlayerState();
}

class _EffectPlayerState extends State<_EffectPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  List<_Particle>? _ps;
  Rect? _area;
  Offset? _origin;

  /// The visible chat screen, measured from the app's own MediaQuery (the
  /// chat page hides the keyboard height from its children, which is why
  /// effects used to end up underneath the keyboard).
  static Rect _chatArea(MediaQueryData mq) {
    final size = mq.size;
    final top = mq.padding.top + 64; // top bar
    final keyboard = mq.viewInsets.bottom;
    final bottom =
        size.height - (keyboard > 0 ? keyboard : mq.padding.bottom) - 64;
    if (bottom - top < 160) {
      return Rect.fromLTRB(0, mq.padding.top, size.width, size.height - keyboard);
    }
    return Rect.fromLTRB(0, top, size.width, bottom);
  }

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<_Particle> _make(Rect area, Offset o) {
    final e = widget.effect;
    final r = math.Random();
    final tps = <String, TextPainter>{};
    final w = area.width, h = area.height;
    return List.generate(VibeLowData.on ? e.count ~/ 2 : e.count, (i) {
      final kind = e.kinds[r.nextInt(e.kinds.length)];
      var size = 6.0 + r.nextDouble() * 8;
      TextPainter? tp;
      if (kind == _Kind.glyph) {
        size = 20 + r.nextDouble() * 20;
        final g = e.glyphs[r.nextInt(e.glyphs.length)];
        tp = tps.putIfAbsent(
          '$g${size.round()}',
          () => TextPainter(
            text: TextSpan(text: g, style: TextStyle(fontSize: size)),
            textDirection: TextDirection.ltr,
          )..layout(),
        );
      }
      var start = o;
      var v = Offset.zero;
      var delay = r.nextDouble() * 0.25;
      var life = 0.55 + r.nextDouble() * 0.3;
      switch (e.emit) {
        case VibeEmit.burst:
          final a = r.nextDouble() * math.pi * 2;
          final speed = 120 + r.nextDouble() * 220;
          start = o;
          v = Offset(math.cos(a), math.sin(a)) * speed;
          delay = 0.06 + r.nextDouble() * 0.12;
        case VibeEmit.rise:
          start = Offset(area.left + r.nextDouble() * w, area.bottom + 30);
          v = Offset((r.nextDouble() - 0.5) * 80, -(h * (0.55 + r.nextDouble() * 0.5)));
          delay = r.nextDouble() * 0.35;
        case VibeEmit.fall:
          start = Offset(area.left + r.nextDouble() * w, area.top - 40);
          v = Offset((r.nextDouble() - 0.5) * 60, h * (0.7 + r.nextDouble() * 0.5));
          delay = r.nextDouble() * 0.4;
        case VibeEmit.cannons:
          final left = i.isEven;
          start = Offset(
            left ? area.left - 10 : area.right + 10,
            area.top + h * 0.85,
          );
          final a = left
              ? -math.pi / 2 + 0.25 + r.nextDouble() * 0.6
              : -math.pi / 2 - 0.25 - r.nextDouble() * 0.6;
          final speed = h * (0.55 + r.nextDouble() * 0.45);
          v = Offset(math.cos(a), math.sin(a)) * speed;
          delay = r.nextDouble() * 0.12;
          life = 0.7 + r.nextDouble() * 0.25;
      }
      return _Particle(
        kind: kind,
        start: start,
        velocity: v,
        size: size,
        delay: delay,
        life: life,
        spin: (r.nextDouble() - 0.5) * 12,
        sway: r.nextDouble() * math.pi * 2,
        color: e.colors[r.nextInt(e.colors.length)],
        tp: tp,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final area = _area ??= _chatArea(MediaQuery.of(context));
    final a = widget.anchor;
    final origin = _origin ??= a == null
        ? area.center
        : Offset(
            a.dx
                .clamp(area.left + 80, math.max(area.left + 80, area.right - 80))
                .toDouble(),
            a.dy
                .clamp(area.top + 60, math.max(area.top + 60, area.bottom - 60))
                .toDouble(),
          );
    final ps = _ps ??= _make(area, origin);
    const big = 150.0;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Big emoji: pop in, hold with a little wobble, shrink away.
          double scale;
          double alpha = 1;
          if (t < 0.14) {
            scale = Curves.easeOutBack.transform(t / 0.14);
          } else if (t < 0.62) {
            scale = 1 + 0.05 * math.sin((t - 0.14) / 0.48 * math.pi * 3);
          } else {
            final u = ((t - 0.62) / 0.22).clamp(0.0, 1.0);
            scale = 1 - 0.5 * Curves.easeIn.transform(u);
            alpha = 1 - u;
          }
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _EffectPainter(
                    t: t,
                    ps: ps,
                    gravity: switch (widget.effect.emit) {
                      VibeEmit.burst => 160,
                      VibeEmit.cannons => 520,
                      VibeEmit.rise => -40,
                      VibeEmit.fall => 120,
                    },
                    glow: widget.effect.colors.first,
                    origin: origin,
                  ),
                ),
              ),
              if (alpha > 0)
                Positioned(
                  left: origin.dx - big / 2,
                  top: origin.dy - big / 2,
                  width: big,
                  height: big,
                  child: Opacity(
                    opacity: alpha.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale.clamp(0.0, 2.0),
                      child: VibeAnimatedEmoji(widget.effect.emoji, size: big),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  final double t;
  final List<_Particle> ps;
  final double gravity;
  final Color glow;
  final Offset origin;
  _EffectPainter({
    required this.t,
    required this.ps,
    required this.gravity,
    required this.glow,
    required this.origin,
  });

  Path _spark(Offset c, double r) {
    final p = Path()..moveTo(c.dx, c.dy - r);
    p.quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy);
    p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r);
    p.quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy);
    p.quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Soft glow behind the big emoji.
    final g = t < 0.15 ? t / 0.15 : (1 - (t - 0.15) / 0.6).clamp(0.0, 1.0);
    if (g > 0) {
      canvas.drawCircle(
        origin,
        110,
        Paint()
          ..color = glow.withValues(alpha: 0.28 * g)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }
    for (final p in ps) {
      final u = ((t - p.delay) / p.life).clamp(0.0, 1.0);
      if (u <= 0 || u >= 1) continue;
      final pos =
          p.start +
          p.velocity * u +
          Offset(18 * math.sin(p.sway + u * 6), gravity * u * u);
      final fadeIn = (u / 0.08).clamp(0.0, 1.0);
      final fadeOut = 1 - Curves.easeIn.transform(((u - 0.65) / 0.35).clamp(0.0, 1.0));
      final a = (fadeIn * fadeOut).clamp(0.0, 1.0);
      if (a <= 0) continue;
      final paint = Paint()..color = p.color.withValues(alpha: a);
      switch (p.kind) {
        case _Kind.dot:
          canvas.drawCircle(pos, p.size * 0.4, paint);
        case _Kind.spark:
          canvas.drawPath(_spark(pos, p.size * (1 - 0.3 * u) + 2), paint);
        case _Kind.ember:
          final flicker = 0.65 + 0.35 * math.sin(t * 50 + p.spin);
          canvas.drawCircle(
            pos,
            p.size * 0.55 * (1 - 0.5 * u),
            Paint()
              ..color = p.color.withValues(alpha: a * flicker)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
          );
        case _Kind.confetti:
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(p.spin * u);
          // Flip like paper turning in the air.
          canvas.scale(1, math.cos(p.sway + u * 14).abs() * 0.8 + 0.2);
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 1.2,
              height: p.size * 0.5,
            ),
            paint,
          );
          canvas.restore();
        case _Kind.glyph:
          final tp = p.tp;
          if (tp == null) break;
          canvas.saveLayer(
            null,
            Paint()..color = Colors.white.withValues(alpha: a),
          );
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(0.25 * math.sin(p.sway + u * 5));
          canvas.scale(0.7 + 0.3 * Curves.easeOutBack.transform(fadeIn));
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_EffectPainter old) => old.t != t;
}
