// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vibe welcome tour (4 swipeable pages with animated illustrations).
/// Port of the web app's WelcomeScreen.
class VibeWelcome extends StatefulWidget {
  final VoidCallback onDone;
  const VibeWelcome({required this.onDone, super.key});

  @override
  State<VibeWelcome> createState() => _VibeWelcomeState();
}

const Color _lavender = Color(0xFFC9CFFF);
const Color _glow = Color(0xFF8B97FF);

class _Fact {
  final IconData icon;
  final String title;
  final String text;
  const _Fact(this.icon, this.title, this.text);
}

class _PageData {
  final String kicker;
  final String title;
  final String body;
  final Widget Function() hero;
  final List<_Fact> facts;
  const _PageData(this.kicker, this.title, this.body, this.hero, this.facts);
}

final List<_PageData> _pages = [
  _PageData(
    'Welcome to Vibe',
    'Chat that stays between you and them',
    'Vibe is a private messenger built on Matrix, an open standard for secure communication. Here is how it keeps you safer, in 30 seconds.',
    () => const _HeroWelcome(),
    const [
      _Fact(
        Icons.lock,
        'Private by default',
        'Chats you start in Vibe are end-to-end encrypted.',
      ),
      _Fact(
        Icons.person,
        'No phone number',
        'Sign up with just a username and password.',
      ),
    ],
  ),
  _PageData(
    'How it works',
    'Locked before it leaves your phone',
    'Each message is scrambled on your device and only unlocked on the devices in that chat. Even the server in the middle only carries scrambled text.',
    () => const _HeroTransit(),
    const [
      _Fact(
        Icons.verified_user,
        'Server cannot read it',
        'Message content is unreadable to the server and to anyone who intercepts it.',
      ),
      _Fact(
        Icons.visibility_off,
        'Be aware',
        'Servers can still see who chats with whom and when. Content stays private.',
      ),
    ],
  ),
  _PageData(
    'Why it is safer',
    'Your keys stay on your devices',
    'Every device you sign in on creates its own keys. To read old messages on a new phone, you use a recovery key that only you hold.',
    () => const _HeroKeys(),
    const [
      _Fact(
        Icons.vpn_key,
        'Back up once',
        'Set up message backup in Settings, Security, Encryption & Keys.',
      ),
      _Fact(
        Icons.lock,
        'Keep the key safe',
        'Lose the key and every device, and old messages stay locked. That is the price of real privacy.',
      ),
    ],
  ),
  _PageData(
    'The little things',
    'Safer in the details too',
    'Privacy is not just encryption. Vibe keeps the small stuff quiet as well.',
    () => const _HeroSmall(),
    const [
      _Fact(
        Icons.notifications,
        'Quiet notifications',
        'Push alerts say "New message". They never include what was written.',
      ),
      _Fact(
        Icons.code,
        'Open standard',
        'Built on Matrix, a public protocol anyone can inspect, not a closed system.',
      ),
      _Fact(
        Icons.check,
        'Delete for everyone',
        'Remove your own messages from the chat for all members.',
      ),
    ],
  ),
];

class _VibeWelcomeState extends State<VibeWelcome> {
  final PageController _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  void _finish() {
    HapticFeedback.lightImpact();
    widget.onDone();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pc.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // soft blurple glow at the top
          Positioned(
            left: -80,
            right: -80,
            top: -60,
            height: 360,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.62,
                    colors: [
                      cs.primary.withAlpha(72),
                      cs.primary.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: cs.primary.withAlpha(46),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.lock,
                            size: 16,
                            color: _lavender,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Vibe',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isLast ? 0 : 1,
                          child: TextButton(
                            onPressed: _isLast ? null : _finish,
                            style: TextButton.styleFrom(
                              foregroundColor: _lavender,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('Skip'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _pages.length,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _page = i);
                    },
                    itemBuilder: (context, i) =>
                        _WelcomePage(_pages[i], active: i == _page),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < _pages.length; i++)
                            GestureDetector(
                              onTap: () => _pc.animateToPage(
                                i,
                                duration: const Duration(milliseconds: 380),
                                curve: Curves.easeOutCubic,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                margin: const EdgeInsets.only(right: 8),
                                width: i == _page ? 28 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: i == _page
                                      ? cs.primary
                                      : cs.outlineVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          minimumSize: const Size(0, 48),
                          padding: EdgeInsets.symmetric(
                            horizontal: _isLast ? 28 : 24,
                          ),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_isLast ? 'Get started' : 'Next'),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatefulWidget {
  final _PageData data;
  final bool active;
  const _WelcomePage(this.data, {required this.active});

  @override
  State<_WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<_WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _in.forward();
  }

  @override
  void didUpdateWidget(_WelcomePage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _in.forward(from: 0);
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Widget _rise(double begin, double end, Widget child) {
    final curve = CurvedAnimation(
      parent: _in,
      curve: Interval(begin, math.min(end, 1.0), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.data;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rise(0.0, 0.5, d.hero()),
              const SizedBox(height: 16),
              _rise(
                0.1,
                0.55,
                Text(
                  d.kicker.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: _lavender,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _rise(
                0.15,
                0.6,
                Text(
                  d.title,
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _rise(
                0.2,
                0.65,
                Text(
                  d.body,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < d.facts.length; i++)
                _rise(
                  0.3 + 0.1 * i,
                  0.75 + 0.1 * i,
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FactCard(d.facts[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactCard extends StatelessWidget {
  final _Fact fact;
  const _FactCard(this.fact);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(46),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(fact.icon, size: 22, color: _lavender),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fact.text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- heroes

class _HeroFrame extends StatelessWidget {
  final Widget child;
  const _HeroFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 190,
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.primary.withAlpha(64)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary.withAlpha(56), cs.primary.withAlpha(15)],
        ),
      ),
      child: child,
    );
  }
}

class _HeroWelcome extends StatefulWidget {
  const _HeroWelcome();
  @override
  State<_HeroWelcome> createState() => _HeroWelcomeState();
}

class _HeroWelcomeState extends State<_HeroWelcome>
    with SingleTickerProviderStateMixin {
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _HeroFrame(
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final t = loop.value;
          // lock bounce at 70-95% of the loop
          double lockScale = 1, lockRot = 0;
          if (t > 0.7 && t < 0.95) {
            final u = (t - 0.7) / 0.25;
            lockScale = 1 + 0.18 * math.sin(u * math.pi);
            lockRot = -0.14 * math.sin(u * math.pi);
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                () {
                  final p = (t + i / 3) % 1.0;
                  return Opacity(
                    opacity: 0.7 * (1 - p),
                    child: Transform.scale(
                      scale: 0.6 + 1.6 * p,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _glow.withAlpha(128),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, v, child) =>
                    Transform.scale(scale: v.clamp(0.0, 1.3), child: child),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5FB),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                      bottomLeft: Radius.circular(8),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'vibe',
                        style: TextStyle(
                          fontSize: 32,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF141826),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Transform.rotate(
                        angle: lockRot,
                        child: Transform.scale(
                          scale: lockScale,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _Node extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final bool dim;
  const _Node(this.icon, this.label, {this.sub, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: _lavender),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: dim ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _HeroTransit extends StatefulWidget {
  const _HeroTransit();
  @override
  State<_HeroTransit> createState() => _HeroTransitState();
}

class _HeroTransitState extends State<_HeroTransit>
    with SingleTickerProviderStateMixin {
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }

  double _lerpWin(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  Widget _packet(
    double progress,
    double opacity,
    double plainOpacity,
    double scrambledOpacity,
  ) {
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Positioned(
            left: progress * math.max(0, c.maxWidth - 44),
            top: 9,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                height: 26,
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: plainOpacity.clamp(0.0, 1.0),
                      child: const Text(
                        'Hi 👋',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: scrambledOpacity.clamp(0.0, 1.0),
                      child: const Text(
                        '•••••',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _track(Widget packet) => Expanded(
    child: SizedBox(
      height: 44,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 21,
            child: Row(
              children: List.generate(
                14,
                (_) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 2,
                    color: _glow.withAlpha(115),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: packet),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return _HeroFrame(
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final t = loop.value;
          // packet 1: you -> server (plain turns into scrambled)
          final p1 = Curves.easeInOutCubic.transform(_lerpWin(t, 0.08, 0.55));
          final o1 = t < 0.08
              ? t / 0.08
              : t < 0.92
              ? 1.0
              : (1 - t) / 0.08;
          final scr1 = _lerpWin(t, 0.18, 0.30);
          // packet 2: server -> friend (scrambled turns into plain)
          final p2 = Curves.easeInOutCubic.transform(_lerpWin(t, 0.55, 0.92));
          final o2 = t < 0.45
              ? 0.0
              : t < 0.55
              ? (t - 0.45) / 0.10
              : t < 0.92
              ? 1.0
              : (1 - t) / 0.08;
          final plain2 = _lerpWin(t, 0.62, 0.85);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                const _Node(Icons.smartphone, 'You'),
                _track(_packet(p1, o1, 1 - scr1, scr1)),
                const _Node(
                  Icons.dns,
                  'Server',
                  sub: 'sees •••••',
                  dim: true,
                ),
                _track(_packet(p2, o2, plain2, 1 - plain2)),
                const _Node(Icons.smartphone, 'Friend'),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroKeys extends StatefulWidget {
  const _HeroKeys();
  @override
  State<_HeroKeys> createState() => _HeroKeysState();
}

class _HeroKeysState extends State<_HeroKeys>
    with SingleTickerProviderStateMixin {
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }

  Widget _device(double badge) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 80,
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 76,
            height: 96,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Icon(Icons.smartphone, size: 34, color: cs.onSurface),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Transform.scale(
              scale: badge,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.vpn_key, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _HeroFrame(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1400),
        builder: (context, v, _) => AnimatedBuilder(
          animation: loop,
          builder: (context, _) {
            final t = loop.value;
            final breathe = 1 + 0.06 * math.sin(t * 2 * math.pi).abs();
            double pulse(double phase) {
              final p = (t + phase) % 1.0;
              return math.sin(p * math.pi);
            }

            double badgeScale(double a, double b) =>
                Curves.elasticOut.transform(((v - a) / (b - a)).clamp(0.0, 1.0));

            return Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _device(badgeScale(0.25, 0.7)),
                    const SizedBox(width: 12),
                    Transform.scale(
                      scale: breathe,
                      child: Container(
                        width: 92,
                        height: 112,
                        decoration: BoxDecoration(
                          color: cs.primary.withAlpha(46),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_user, size: 40, color: _lavender),
                            SizedBox(height: 6),
                            Text(
                              'Recovery key',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _lavender,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _device(badgeScale(0.45, 0.9)),
                  ],
                ),
                Align(
                  alignment: const Alignment(-0.42, 0),
                  child: Opacity(
                    opacity: pulse(0),
                    child: Transform.translate(
                      offset: Offset(-10 + 20 * ((t) % 1.0), 0),
                      child: _pulseLine(),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0.42, 0),
                  child: Opacity(
                    opacity: pulse(0.5),
                    child: Transform.translate(
                      offset: Offset(-10 + 20 * ((t + 0.5) % 1.0), 0),
                      child: _pulseLine(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pulseLine() => Container(
    width: 30,
    height: 2,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0x008B97FF), _glow, Color(0x008B97FF)],
      ),
    ),
  );
}

class _HeroSmall extends StatelessWidget {
  const _HeroSmall();

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String sub,
    bool ghost = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final fg = ghost ? cs.onSurface : const Color(0xFF141826);
    final subColor = ghost ? cs.onSurfaceVariant : const Color(0xFF4A5164);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ghost ? const Color(0x14F4F5FB) : const Color(0xFFF4F5FB),
        borderRadius: BorderRadius.circular(20),
        border: ghost
            ? Border.all(color: _glow.withAlpha(128))
            : null,
        boxShadow: ghost
            ? null
            : const [
                BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ghost ? cs.primary.withAlpha(46) : cs.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: ghost ? _lavender : Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                Text(sub, style: TextStyle(fontSize: 12, color: subColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _HeroFrame(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        builder: (context, v, _) {
          double part(double a, double b) =>
              Curves.easeOutCubic.transform(((v - a) / (b - a)).clamp(0.0, 1.0));
          Widget slide(double p, Widget child) => Opacity(
            opacity: p,
            child: Transform.translate(
              offset: Offset(0, -18 * (1 - p)),
              child: child,
            ),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                slide(
                  part(0.0, 0.55),
                  _card(
                    context,
                    icon: Icons.notifications,
                    title: 'Vibe',
                    sub: 'New message',
                  ),
                ),
                const SizedBox(height: 10),
                slide(
                  part(0.4, 1.0),
                  _card(
                    context,
                    icon: Icons.visibility_off,
                    title: 'Message text',
                    sub: 'never leaves the chat',
                    ghost: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
