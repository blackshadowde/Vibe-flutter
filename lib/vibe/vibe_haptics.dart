// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// All haptics go through here so Settings > Appearance can switch them off.
abstract class VibeHaptics {
  static bool get enabled => AppSettings.vibeHaptics.value;
  static int _lastMs = 0;

  /// Two haptics within 70 ms are one tap (VibePressable + global listener).
  static bool _gate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < 70) return false;
    _lastMs = now;
    return true;
  }

  static void selection() {
    if (enabled && _gate()) HapticFeedback.selectionClick();
  }

  static void light() {
    if (enabled && _gate()) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled && _gate()) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled && _gate()) HapticFeedback.heavyImpact();
  }
}

/// Wraps the whole app: a short, still tap on anything clickable (buttons,
/// list tiles, switches, chips, icons) gives a light haptic.
class VibeTapHaptics extends StatefulWidget {
  final Widget child;
  const VibeTapHaptics({super.key, required this.child});

  @override
  State<VibeTapHaptics> createState() => _VibeTapHapticsState();
}

class _VibeTapHapticsState extends State<VibeTapHaptics> {
  final Map<int, Offset> _downPos = {};
  final Map<int, int> _downAt = {};

  bool _clickableAt(PointerEvent e) {
    try {
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, e.position, e.viewId);
      for (final entry in result.path) {
        final t = entry.target;
        if (t is RenderMouseRegion && t.cursor == SystemMouseCursors.click) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      _downPos[e.pointer] = e.position;
      _downAt[e.pointer] = DateTime.now().millisecondsSinceEpoch;
    },
    onPointerCancel: (e) {
      _downPos.remove(e.pointer);
      _downAt.remove(e.pointer);
    },
    onPointerUp: (e) {
      final p = _downPos.remove(e.pointer);
      final t = _downAt.remove(e.pointer);
      if (p == null || t == null || !VibeHaptics.enabled) return;
      final quick = DateTime.now().millisecondsSinceEpoch - t < 350;
      if (quick && (e.position - p).distance < 18 && _clickableAt(e)) {
        VibeHaptics.light();
      }
    },
    child: widget.child,
  );
}
