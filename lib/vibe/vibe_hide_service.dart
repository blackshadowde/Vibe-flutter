// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The permanent "Vibe · Connected for notifications" notification.
///
/// Android requires every app that stays connected in the background to
/// show one; an app can't hide it itself. But you can switch off its
/// category ("Vibe connection") in Android's settings: the connection keeps
/// running and messages still arrive, only that notification goes away.
abstract class VibeHideService {
  static const _channel = MethodChannel('vibe/system');
  static const channelId = 'vibe_connection';

  static Future<void> open(BuildContext context) async {
    final ok = await showVibeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_paused, size: 32),
        title: const Text('Hide the permanent notification'),
        content: const Text(
          'Android shows it so Vibe may stay connected in the background. '
          'On the next screen, turn off "Vibe connection".\n\n'
          'Vibe stays connected and your messages still arrive right away; '
          'only that notification disappears. Message notifications are a '
          'separate category and stay on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _channel.invokeMethod('openChannelSettings', {
        'channel': channelId,
      });
    } catch (_) {}
  }
}
