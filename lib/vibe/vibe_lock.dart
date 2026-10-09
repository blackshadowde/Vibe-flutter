// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_activity_pill.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:matrix/matrix.dart';

/// Locked chats: hidden from the chat list and rail, opened only after
/// fingerprint / face / phone PIN. Stored on this phone only.
abstract class VibeLock {
  static const _key = 'chat.vibe.locked_rooms';
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static DateTime _unlockedUntil = DateTime(2000);

  static Set<String> locked() {
    try {
      return (AppSettings.store.getStringList(_key) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  static bool isLocked(String roomId) => locked().contains(roomId);

  /// After one successful unlock, locked chats stay open for 5 minutes.
  static bool get sessionUnlocked => DateTime.now().isBefore(_unlockedUntil);

  static void relock() => _unlockedUntil = DateTime(2000);

  static Future<bool> authenticate(String reason) async {
    if (sessionUnlocked) return true;
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      final ok = await auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        _unlockedUntil = DateTime.now().add(const Duration(minutes: 5));
      }
      return ok;
    } catch (e) {
      Logs().w('Vibe lock: authentication failed', e);
      return false;
    }
  }

  static Future<void> setLocked(String roomId, bool lock) async {
    final s = locked();
    lock ? s.add(roomId) : s.remove(roomId);
    await AppSettings.store.setStringList(_key, s.toList());
    changes.value++;
  }

  /// Lock / unlock from the chat's long-press sheet.
  static Future<void> toggle(BuildContext context, Room room) async {
    final messenger = ScaffoldMessenger.of(context);
    final locking = !isLocked(room.id);
    if (locking) {
      bool supported;
      try {
        supported = await LocalAuthentication().isDeviceSupported();
      } catch (_) {
        supported = false;
      }
      if (!supported) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Set a screen lock (fingerprint or PIN) on your phone first',
            ),
          ),
        );
        return;
      }
    }
    relock();
    final ok = await authenticate(
      locking ? 'Confirm to lock this chat' : 'Confirm to unlock this chat',
    );
    if (!ok) return;
    await setLocked(room.id, locking);
    VibeHaptics.medium();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          locking
              ? '🔒 Chat locked. Find it under "Locked chats".'
              : 'Chat unlocked',
        ),
      ),
    );
  }

  /// "🔒 Locked chats" entry: unlock, then pick a chat.
  static Future<void> openFolder(
    BuildContext context,
    Client client,
    void Function(Room room) onOpen,
  ) async {
    final ok = await authenticate('Unlock your locked chats');
    if (!ok || !context.mounted) return;
    final rooms = client.rooms.where((r) => isLocked(r.id)).toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '🔒 Locked chats',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            if (rooms.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text('No locked chats.'),
              ),
            for (final r in rooms)
              Builder(
                builder: (ctx) {
                  final name = r.getLocalizedDisplayname(
                    MatrixLocals(L10n.of(ctx)),
                  );
                  return ListTile(
                    leading: Avatar(
                      mxContent: r.avatar,
                      name: name,
                      size: 42,
                      client: r.client,
                    ),
                    title: Text(name),
                    trailing: VibeUnreadBadge(room: r),
                    onTap: () {
                      Navigator.pop(ctx);
                      onOpen(r);
                    },
                    onLongPress: () async {
                      Navigator.pop(ctx);
                      await toggle(context, r);
                    },
                  );
                },
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'Long-press a chat here to unlock it.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a chat screen. Locked chats ask for fingerprint / PIN first, also
/// when opened from a notification.
class VibeLockGate extends StatefulWidget {
  final String roomId;
  final Widget child;
  const VibeLockGate({required this.roomId, required this.child, super.key});

  @override
  State<VibeLockGate> createState() => _VibeLockGateState();
}

class _VibeLockGateState extends State<VibeLockGate> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _open = !VibeLock.isLocked(widget.roomId) || VibeLock.sessionUnlocked;
    if (!_open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  Future<void> _unlock() async {
    final ok = await VibeLock.authenticate('Unlock this chat');
    if (ok && mounted) setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_open) return widget.child;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'This chat is locked',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                foregroundColor: Colors.white,
              ),
              onPressed: _unlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
