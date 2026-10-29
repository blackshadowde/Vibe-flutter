// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:vibe/widgets/matrix.dart';

/// Makes a new feature noticeable until people know it: a soft glow sweeps
/// over [child] and a small "New" label sits next to it, for the first
/// [times] times it is shown, then it looks normal for good.
///
/// Reuse for any new feature: give it a unique [id], e.g.
/// `VibeNewHint(id: 'quote_part', child: ...)`.
class VibeNewHint extends StatefulWidget {
  final String id;
  final Widget child;
  final int times;
  const VibeNewHint({
    required this.id,
    required this.child,
    this.times = 5,
    super.key,
  });

  @override
  State<VibeNewHint> createState() => _VibeNewHintState();
}

class _VibeNewHintState extends State<VibeNewHint>
    with SingleTickerProviderStateMixin {
  bool _show = false;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _show) return;
    try {
      final store = Matrix.of(context).store;
      final key = 'vibe_hint_${widget.id}';
      final seen = store.getInt(key) ?? 0;
      if (seen >= widget.times) return;
      store.setInt(key, seen + 1);
      _show = true;
      // once the menu has landed
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _c.repeat(count: 2);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.6 + 3.2 * t, 0),
                      end: Alignment(-0.6 + 3.2 * t, 0),
                      colors: [
                        cs.primary.withValues(alpha: 0),
                        cs.primary.withValues(alpha: 0.18),
                        cs.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
        Positioned(
          right: 16,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'New',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
