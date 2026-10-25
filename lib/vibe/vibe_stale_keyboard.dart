// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';

/// Sometimes the phone keeps reporting a keyboard height after the keyboard
/// is gone (a swipe back, switching apps, a lock screen while typing). The
/// chat page then keeps its message bar lifted "in the middle" with an empty
/// gap under it.
///
/// If a keyboard height is reported, no text field has focus, and that stays
/// so for a moment, the height is ignored for the page below. As soon as the
/// phone reports 0 again, or any text field is focused, nothing is changed.
class VibeStaleKeyboardGuard extends StatefulWidget {
  final Widget child;
  const VibeStaleKeyboardGuard({required this.child, super.key});

  @override
  State<VibeStaleKeyboardGuard> createState() => _VibeStaleKeyboardGuardState();
}

class _VibeStaleKeyboardGuardState extends State<VibeStaleKeyboardGuard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    FocusManager.instance.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _check();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _check();

  bool _textFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _keyboardReported() {
    if (!mounted) return false;
    return View.of(context).viewInsets.bottom > 0;
  }

  void _check() {
    if (!mounted) return;
    _timer?.cancel();
    if (!_keyboardReported() || _textFocused()) {
      if (_stale) setState(() => _stale = false);
      return;
    }
    // Normal keyboard hiding finishes well within this time.
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final stale = _keyboardReported() && !_textFocused();
      if (stale != _stale) setState(() => _stale = stale);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_stale) return widget.child;
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: widget.child,
    );
  }
}
