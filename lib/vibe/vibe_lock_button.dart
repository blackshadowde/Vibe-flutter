// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/vibe_strict.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// The chat's lock, top right: a small filled lock whose colour says how
/// safe the chat is.
/// - green: end-to-end encrypted and everyone's devices are verified
/// - amber: encrypted, but someone has a device you haven't verified
/// - red, open: not encrypted
/// Tap for the encryption page.
class VibeLockButton extends StatefulWidget {
  final Room room;
  const VibeLockButton({required this.room, super.key});

  @override
  State<VibeLockButton> createState() => _VibeLockButtonState();
}

class _VibeLockButtonState extends State<VibeLockButton> {
  EncryptionHealthState? _health;
  StreamSubscription? _keys;

  @override
  void initState() {
    super.initState();
    _check();
    // re-check when someone's devices or verification change
    _keys = widget.room.client.onSync.stream
        .where((s) => s.deviceLists != null)
        .listen((_) => _check());
  }

  @override
  void didUpdateWidget(VibeLockButton old) {
    super.didUpdateWidget(old);
    if (old.room.id != widget.room.id) _check();
  }

  Future<void> _check() async {
    if (!widget.room.encrypted) return;
    try {
      final h = await widget.room.calcEncryptionHealthState();
      if (mounted && h != _health) setState(() => _health = h);
    } catch (_) {}
  }

  @override
  void dispose() {
    _keys?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final encrypted = room.encrypted;
    final Color color;
    final String tip;
    if (!encrypted) {
      color = const Color(0xFFDA373C);
      tip = 'Not encrypted';
    } else if (_health == EncryptionHealthState.unverifiedDevices) {
      color = const Color(0xFFF0B232);
      tip = 'Encrypted · some devices aren\'t verified';
    } else {
      color = const Color(0xFF23A55A);
      tip = VibeStrict.isOn(room)
          ? 'Strict end-to-end encryption'
          : 'End-to-end encrypted';
    }
    return Tooltip(
      message: tip,
      child: VibePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.go('/rooms/${room.id}/encryption'),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Container(
                  key: ValueKey('$encrypted$_health'),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withAlpha(0x26),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: encrypted
                      ? VibeLockShield(
                          strict: VibeStrict.isOn(room),
                          color: color,
                          size: 18,
                        )
                      : Icon(Icons.lock_open, size: 17, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
