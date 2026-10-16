// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:flutter/material.dart';

/// Every pane / page that slides up closes with a swipe down that follows
/// the finger: the pane moves with it, and on letting go it either slides
/// away (pulled far enough, or flicked down) or springs back.
///
/// Works on the pane's scrolling list too: pulling down while the list is at
/// its top moves the pane. Nested ones do nothing (the outer one handles it).
class VibeSheetDragClose extends StatefulWidget {
  final Widget child;
  const VibeSheetDragClose({required this.child, super.key});

  @override
  State<VibeSheetDragClose> createState() => _VibeSheetDragCloseState();
}

class _Marker extends InheritedWidget {
  const _Marker({required super.child});
  @override
  bool updateShouldNotify(_Marker old) => false;
}

class _VibeSheetDragCloseState extends State<VibeSheetDragClose> {
  bool _dragging = false;
  bool _closing = false;

  // ignore: invalid_use_of_protected_member
  AnimationController? get _ctrl => (ModalRoute.of(context) as TransitionRoute?)?.controller;

  double get _height {
    final h = context.size?.height ?? 0;
    return h > 50 ? h : MediaQuery.sizeOf(context).height;
  }

  void _move(double dy) {
    final c = _ctrl;
    if (c == null || _closing) return;
    if (!_dragging) {
      if (dy <= 0) return; // only a pull down starts it
      _dragging = true;
      ModalRoute.of(context)?.navigator?.didStartUserGesture();
    }
    c.value = (c.value - dy / _height).clamp(0.0, 1.0);
  }

  void _end(double velocity) {
    final c = _ctrl;
    if (!_dragging || c == null) return;
    _dragging = false;
    final nav = ModalRoute.of(context)?.navigator;
    void done() => nav?.didStopUserGesture();
    if (velocity > 800 || c.value < 0.72) {
      _closing = true;
      VibeHaptics.light();
      Navigator.of(context).pop();
      if (c.isAnimating) {
        late AnimationStatusListener l;
        l = (s) {
          if (s == AnimationStatus.dismissed || s == AnimationStatus.completed) {
            c.removeStatusListener(l);
            done();
          }
        };
        c.addStatusListener(l);
      } else {
        done();
      }
    } else {
      c.animateTo(1, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic).whenComplete(done);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _move(-n.overscroll);
    } else if (_dragging && n is ScrollUpdateNotification && n.dragDetails != null) {
      _move(-(n.scrollDelta ?? 0));
    } else if (n is ScrollEndNotification) {
      _end(n.dragDetails?.velocity.pixelsPerSecond.dy ?? 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<_Marker>() != null) return widget.child;
    return _Marker(
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: GestureDetector(
          // the parts of the pane that don't scroll
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) => _move(d.delta.dy),
          onVerticalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
          onVerticalDragCancel: () => _end(0),
          child: ScrollConfiguration(
            // Clamping physics reports the pull-down as overscroll everywhere.
            behavior: ScrollConfiguration.of(context).copyWith(physics: const ClampingScrollPhysics()),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
