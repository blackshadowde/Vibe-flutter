// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// Vibe X's little date at the top of a chat: while you scroll, it shows the
/// day of the messages at the top of the screen, then fades away a moment
/// after you stop.
class VibeDatePill extends StatefulWidget {
  final AutoScrollController scroll;
  final List<Event> Function() events;
  const VibeDatePill({required this.scroll, required this.events, super.key});

  @override
  State<VibeDatePill> createState() => _VibeDatePillState();
}

class _VibeDatePillState extends State<VibeDatePill> {
  String? _label;
  bool _shown = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(VibeDatePill old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_onScroll);
      widget.scroll.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    _hide?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.scroll.hasClients) return;
    // only while you scroll (not when the chat jumps by itself)
    if (widget.scroll.position.userScrollDirection == ScrollDirection.idle) {
      return;
    }
    final label = _find();
    if (label == null) return;
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _shown = false);
    });
    if (label != _label || !_shown) {
      setState(() {
        _label = label;
        _shown = true;
      });
    }
  }

  /// The day of the message right under the pill.
  String? _find() {
    final me = context.findRenderObject() as RenderBox?;
    if (me == null || !me.attached) return null;
    final line = me.localToGlobal(Offset.zero).dy + 40;
    final events = widget.events();
    int? best;
    double bestY = double.infinity;
    for (final e in widget.scroll.tagMap.entries) {
      final rb = e.value.context.findRenderObject();
      if (rb is! RenderBox || !rb.attached || !rb.hasSize) continue;
      final y = rb.localToGlobal(Offset.zero).dy;
      final bottom = y + rb.size.height;
      if (bottom < line) continue; // above the pill
      if (y < bestY) {
        bestY = y;
        best = e.key;
      }
    }
    if (best == null || best < 0 || best >= events.length) return null;
    return _format(events[best].originServerTs);
  }

  String _format(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (d.year == now.year) return DateFormat('EEE, d MMM').format(d);
    return DateFormat('EEE, d MMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: Duration(milliseconds: _shown ? 150 : 350),
        child: AnimatedSlide(
          offset: _shown ? Offset.zero : const Offset(0, -0.3),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: dark ? const Color(0xEE2B2D31) : const Color(0xEEEBEDEF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _label ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: dark ? const Color(0xFFDBDEE1) : const Color(0xFF313338),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
