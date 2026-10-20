// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_direct.dart';
import 'package:fluffychat/vibe/vibe_ntfy.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/vibe/vibe_hide_service.dart';
import 'package:flutter/material.dart';

/// Settings > Notifications: Direct connection (like Vibgram, default) or
/// Built-in (ntfy). Firebase was removed: it duplicated notifications.
class VibePushModeTiles extends StatefulWidget {
  const VibePushModeTiles({super.key});

  @override
  State<VibePushModeTiles> createState() => _VibePushModeTilesState();
}

class _VibePushModeTilesState extends State<VibePushModeTiles> {
  bool _busy = false;
  int _bgCheck = 0;

  Future<void> _set(String mode) async {
    if (_busy || mode == AppSettings.vibePushMode.value) return;
    final push = Matrix.of(context).backgroundPush;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await AppSettings.vibePushMode.setItem(mode);
      if (mode != 'direct') await VibeDirect.stop();
      if (mode == 'builtin' || mode == 'direct') {
        await VibeNtfy.askBatteryExemption();
      }
      if (mode != 'builtin') await VibeNtfy.stop();
      if (!mounted) return;
      await push?.setupPush(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            switch (mode) {
              'direct' => 'Direct connection on',
              _ => 'Built-in notifications on',
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile(String mode, String title, String subtitle, IconData icon) {
    final selected = AppSettings.vibePushMode.value == mode;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? cs.primary : null,
      ),
      onTap: _busy ? null : () => _set(mode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(
            'How notifications arrive',
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        _tile(
          'direct',
          'Direct connection (recommended)',
          'Like Vibgram: Vibe stays connected to your server and shows '
              'messages the moment they arrive, with nothing in between. '
              'Shows a small permanent notification (you can hide it below).',
          Icons.bolt,
        ),
        _tile(
          'builtin',
          'Built-in, no Google',
          'Vibe keeps its own connection (ntfy). Works without Google '
              'services. Shows a small permanent notification and uses a '
              'little more battery.',
          Icons.cell_tower,
        ),
        // Without this, stock Android (Pixel) stops Vibe's connection while
        // the phone sleeps and notifications stop coming.
        FutureBuilder<bool>(
          key: ValueKey(_bgCheck),
          future: VibeNtfy.backgroundAllowed(),
          builder: (context, snap) {
            final ok = snap.data ?? true;
            return ListTile(
              leading: Icon(
                ok ? Icons.battery_charging_full : Icons.battery_alert,
                color: ok ? null : theme.colorScheme.error,
              ),
              title: const Text('Run in the background'),
              subtitle: Text(
                ok
                    ? 'Allowed: notifications keep coming while the phone sleeps'
                    : 'Restricted: notifications may stop while the phone '
                          'sleeps. Tap to allow',
              ),
              onTap: ok
                  ? null
                  : () async {
                      await VibeNtfy.askBatteryExemption();
                      if (mounted) setState(() => _bgCheck++);
                    },
            );
          },
        ),
        ListTile(
            leading: const Icon(Icons.notifications_paused),
            title: const Text('Hide the permanent notification'),
            subtitle: const Text(
              'Keeps the connection, removes the "Connected for '
              'notifications" notification',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => VibeHideService.open(context),
          ),
      ],
    );
  }
}
