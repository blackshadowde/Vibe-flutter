// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_ntfy.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

/// Settings > Notifications: Standard (Firebase) or Built-in (no Google).
class VibePushModeTiles extends StatefulWidget {
  const VibePushModeTiles({super.key});

  @override
  State<VibePushModeTiles> createState() => _VibePushModeTilesState();
}

class _VibePushModeTilesState extends State<VibePushModeTiles> {
  bool _busy = false;

  Future<void> _set(String mode) async {
    if (_busy || mode == AppSettings.vibePushMode.value) return;
    final push = Matrix.of(context).backgroundPush;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await AppSettings.vibePushMode.setItem(mode);
      if (mode == 'builtin') {
        await VibeNtfy.askBatteryExemption();
      } else {
        await VibeNtfy.stop();
      }
      if (!mounted) return;
      await push?.setupPush(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mode == 'builtin'
                ? 'Built-in notifications on'
                : 'Standard notifications on',
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
          'standard',
          'Standard (recommended)',
          'Through Google Firebase. Best battery life and most reliable.',
          Icons.bolt_outlined,
        ),
        _tile(
          'builtin',
          'Built-in, no Google',
          'Vibe keeps its own connection (ntfy). Works without Google '
              'services. Shows a small permanent notification and uses a '
              'little more battery.',
          Icons.cell_tower,
        ),
        Divider(color: theme.dividerColor),
      ],
    );
  }
}
