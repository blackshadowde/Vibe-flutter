// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Lets a scrollable bottom sheet close with a swipe down. The scroll view
/// inside the sheet swallows the drag, so when it is already at the top and
/// the finger keeps pulling down, close the sheet.
class VibeSheetDragClose extends StatefulWidget {
  final Widget child;
  const VibeSheetDragClose({required this.child, super.key});

  @override
  State<VibeSheetDragClose> createState() => _VibeSheetDragCloseState();
}

class _VibeSheetDragCloseState extends State<VibeSheetDragClose> {
  double _pull = 0;
  bool _closing = false;

  bool _onScroll(ScrollNotification n) {
    if (_closing || n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) _pull = 0;
    if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0 &&
        n.metrics.pixels <= n.metrics.minScrollExtent) {
      _pull -= n.overscroll;
      if (_pull > 24) {
        _closing = true;
        Navigator.of(context).maybePop();
      }
    }
    if (n is ScrollUpdateNotification && (n.scrollDelta ?? 0) > 0) {
      _pull = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: _onScroll,
    child: ScrollConfiguration(
      // Clamping physics reports the pull-down as overscroll everywhere.
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(physics: const ClampingScrollPhysics()),
      child: widget.child,
    ),
  );
}
