// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';

/// Shrinks slightly while a finger is down and springs back on release.
/// Uses a [Listener], so taps and long presses of the child keep working.
///
/// Like Telegram, the press only shows once the finger has stayed put for a
/// moment: starting to scroll a list never squeezes (or buzzes) the row
/// under your finger.
class VibePressable extends StatefulWidget {
  final Widget child;
  final double scale;
  const VibePressable({required this.child, this.scale = 0.95, super.key});

  @override
  State<VibePressable> createState() => _VibePressableState();
}

class _VibePressableState extends State<VibePressable> {
  static const _slop = 8.0; // px a finger may wobble and still be a press
  bool _down = false;
  Timer? _timer;
  Offset? _start;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _start = null;
    _set(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) {
      _start = e.position;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 70), () {
        if (_start == null) return;
        VibeHaptics.selection();
        _set(true);
      });
    },
    onPointerMove: (e) {
      final s = _start;
      if (s != null && (e.position - s).distance > _slop) _cancel();
    },
    onPointerUp: (_) {
      // A quick tap: show the squeeze briefly so it still feels pressed.
      if (_timer?.isActive ?? false) {
        _timer!.cancel();
        _set(true);
        Future<void>.delayed(const Duration(milliseconds: 90), () => _set(false));
        _start = null;
        return;
      }
      _cancel();
    },
    onPointerCancel: (_) => _cancel(),
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: Duration(milliseconds: _down ? 90 : 320),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

/// Fade + rise-in, once, with a small per-index delay. Items beyond
/// [maxIndex] (scrolled in later) appear without animation.
class VibeStagger extends StatefulWidget {
  final int index;
  final int maxIndex;
  final double dy;
  final Widget child;
  const VibeStagger({
    required this.index,
    required this.child,
    this.maxIndex = 12,
    this.dy = 18,
    super.key,
  });

  @override
  State<VibeStagger> createState() => _VibeStaggerState();
}

class _VibeStaggerState extends State<VibeStagger>
    with SingleTickerProviderStateMixin {
  /// Rows that already played: a lazily built list re-creates rows that
  /// scroll back in, and they shouldn't fade in a second time.
  static final Set<Key> _seen = {};
  late final bool _play =
      widget.index <= widget.maxIndex &&
      (widget.key == null || _seen.add(widget.key!));
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: _play ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (_play) {
      Future<void>.delayed(Duration(milliseconds: 32 * widget.index), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  late final Animation<Offset> _rise = Tween<Offset>(
    begin: Offset(0, widget.dy),
    end: Offset.zero,
  ).animate(_curve);

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: _PixelSlide(offset: _rise, child: widget.child),
  );
}

/// Moves its child by an animated offset in pixels. Paint-only: the child is
/// never rebuilt or laid out again while it moves.
class _PixelSlide extends AnimatedWidget {
  final Widget child;
  const _PixelSlide({required Animation<Offset> offset, required this.child})
    : super(listenable: offset);

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: (listenable as Animation<Offset>).value,
    transformHitTests: false,
    child: child,
  );
}

/// Builds [child] only once the page or pane it lives in has finished
/// sliding in. Heavy content (grids of pictures, emoji pickers, animated
/// emoji) then never competes with the slide for frames: the pane moves
/// like Telegram's, and the content appears right after. [placeholder] is
/// shown meanwhile (keep it light).
class VibeSettled extends StatefulWidget {
  final Widget child;
  final Widget placeholder;
  const VibeSettled({
    required this.child,
    this.placeholder = const SizedBox.shrink(),
    super.key,
  });

  /// True when the route of [context] has finished its opening animation.
  static bool routeSettled(BuildContext context) {
    final a = ModalRoute.of(context)?.animation;
    return a == null || a.status == AnimationStatus.completed;
  }

  @override
  State<VibeSettled> createState() => _VibeSettledState();
}

class _VibeSettledState extends State<VibeSettled> {
  Animation<double>? _route;
  bool _ready = false;

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && mounted && !_ready) {
      setState(() => _ready = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final a = ModalRoute.of(context)?.animation;
    if (a == null || a.status == AnimationStatus.completed) {
      _ready = true;
      return;
    }
    if (!identical(a, _route)) {
      _route?.removeStatusListener(_onStatus);
      _route = a..addStatusListener(_onStatus);
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : widget.placeholder;
}

/// The smooth, slow-out animation used by every sheet in the app.
/// Telegram-like timing: quick, decelerating open; quicker close.
const AnimationStyle vibeSheetStyle = AnimationStyle(
  duration: Duration(milliseconds: 320),
  reverseDuration: Duration(milliseconds: 220),
  curve: Curves.easeOutCubic,
  reverseCurve: Curves.easeInCubic,
);

/// Every pane that slides up from the bottom goes through here, so they
/// all move the same smooth way: Telegram-like timing, and the pane is its
/// own layer (the slide moves a picture of it instead of repainting it on
/// every frame). Same parameters as [showModalBottomSheet].
Future<T?> showVibeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isDismissible = true,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  AnimationStyle? sheetAnimationStyle,
  bool? showDragHandle,
  bool useRootNavigator = false,
  bool useSafeArea = false,
}) => showModalBottomSheet<T>(
  context: context,
  builder: (ctx) => RepaintBoundary(child: builder(ctx)),
  backgroundColor: backgroundColor,
  clipBehavior: clipBehavior,
  constraints: constraints,
  isDismissible: isDismissible,
  isScrollControlled: isScrollControlled,
  shape: shape,
  sheetAnimationStyle: sheetAnimationStyle ?? vibeSheetStyle,
  showDragHandle: showDragHandle,
  useRootNavigator: useRootNavigator,
  useSafeArea: useSafeArea,
);
