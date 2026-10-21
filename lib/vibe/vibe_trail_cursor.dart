// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The message box cursor, kitty style: when it jumps (tapping elsewhere in
/// the text, a new line, pasting, deleting a word) a fading trail stretches
/// from where it was to where it lands. Small steps (typing a letter) just
/// glide. Blinks when idle; hidden while text is selected.
///
/// Wrap the TextField and give it `cursorColor: Colors.transparent`, so
/// only this cursor shows.
class VibeTrailCursor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget child;
  const VibeTrailCursor({
    required this.controller,
    required this.focusNode,
    required this.child,
    super.key,
  });

  @override
  State<VibeTrailCursor> createState() => _VibeTrailCursorState();
}

class _VibeTrailCursorState extends State<VibeTrailCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  final _repaint = ValueNotifier<int>(0);
  final _stackKey = GlobalKey();
  Rect? _from;
  Rect? _to;
  bool _trail = false;
  bool _visible = false;
  bool _blinkOn = true;
  Timer? _blink;
  DateTime _lastMove = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_schedule);
    widget.focusNode.addListener(_schedule);
    _move.addListener(() => _repaint.value++);
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (!_visible) return;
      // solid while moving / just after typing, blinking when idle
      final idle = DateTime.now().difference(_lastMove).inMilliseconds > 600;
      final next = idle ? !_blinkOn : true;
      if (next != _blinkOn) {
        _blinkOn = next;
        _repaint.value++;
      }
    });
    _schedule();
  }

  @override
  void didUpdateWidget(VibeTrailCursor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_schedule);
      widget.controller.addListener(_schedule);
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_schedule);
      widget.focusNode.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_schedule);
    widget.focusNode.removeListener(_schedule);
    _blink?.cancel();
    _move.dispose();
    _repaint.dispose();
    super.dispose();
  }

  /// Measure after the text field has laid out the change.
  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  RenderEditable? _findEditable() {
    RenderEditable? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = (e.state as EditableTextState).renderEditable;
        return;
      }
      e.visitChildren(visit);
    }

    final ctx = _stackKey.currentContext;
    if (ctx is Element) ctx.visitChildren(visit);
    return found;
  }

  void _measure() {
    if (!mounted) return;
    final sel = widget.controller.selection;
    final show = widget.focusNode.hasFocus && sel.isValid && sel.isCollapsed;
    if (!show) {
      if (_visible) {
        _visible = false;
        _repaint.value++;
      }
      return;
    }
    final editable = _findEditable();
    final stack = _stackKey.currentContext?.findRenderObject();
    if (editable == null || !editable.attached || stack is! RenderBox) return;
    final local = editable.getLocalRectForCaret(TextPosition(offset: sel.extentOffset));
    final topLeft = stack.globalToLocal(editable.localToGlobal(local.topLeft));
    final caret = Rect.fromLTWH(topLeft.dx, topLeft.dy, 2.5, local.height);

    final now = _current;
    _visible = true;
    _lastMove = DateTime.now();
    _blinkOn = true;
    if (now == null || (now.center - caret.center).distance < 0.5) {
      _from = caret;
      _to = caret;
      _repaint.value++;
      return;
    }
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final jump = (now.center - caret.center).distance;
    _from = now;
    _to = caret;
    // a real jump (not one letter): the kitty trail
    _trail = !still && (jump > caret.height * 1.2 || (now.top - caret.top).abs() > 2);
    if (still) {
      _from = caret;
      _repaint.value++;
      return;
    }
    _move.duration = Duration(milliseconds: _trail ? 220 : 70);
    _move.forward(from: 0);
  }

  /// Where the cursor is drawn right now (mid-animation included).
  Rect? get _current {
    final a = _from, b = _to;
    if (a == null || b == null) return b;
    return Rect.lerp(a, b, Curves.easeOutCubic.transform(_move.value));
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Stack(
      key: _stackKey,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _TrailPainter(this, color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrailPainter extends CustomPainter {
  final _VibeTrailCursorState s;
  final Color color;
  _TrailPainter(this.s, this.color) : super(repaint: s._repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (!s._visible) return;
    final from = s._from, to = s._to;
    if (from == null || to == null) return;
    final t = s._move.value;
    // the head races ahead, the tail follows (kitty's smear)
    final head = Rect.lerp(from, to, Curves.easeOutCubic.transform(t))!;
    if (s._trail && t < 1) {
      final tail = Rect.lerp(
        from,
        to,
        Curves.easeInCubic.transform((t * 0.92).clamp(0.0, 1.0)),
      )!;
      final path = Path()
        ..moveTo(tail.left, tail.top)
        ..lineTo(head.left, head.top)
        ..lineTo(head.right, head.top)
        ..lineTo(head.right, head.bottom)
        ..lineTo(head.left, head.bottom)
        ..lineTo(tail.left, tail.bottom)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            tail.center,
            head.center,
            [color.withValues(alpha: 0), color.withValues(alpha: 0.55 * (1 - t * 0.5))],
          ),
      );
    }
    final solid = t < 1 || s._blinkOn;
    if (!solid) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, const Radius.circular(1.5)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.color != color;
}
