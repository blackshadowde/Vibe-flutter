// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_dialog.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/vibe/vibe_app_info.dart';
import 'package:vibe/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// If Vibe crashed (or froze) last time, say so once and offer the report
/// to copy, so the problem can actually be found and fixed. Android keeps
/// the reason, even for crashes inside native code.
abstract class VibeCrashReport {
  static const _channel = MethodChannel('vibe/system');
  static const _seenKey = 'vibe_crash_seen';
  static bool _checked = false;

  static Future<void> check() async {
    if (_checked || !PlatformInfos.isAndroid) return;
    _checked = true;
    try {
      final raw = await _channel.invokeMethod<Map>('lastExit');
      if (raw == null) return;
      final info = Map<String, Object?>.from(raw);
      final time = (info['time'] as num?)?.toInt() ?? 0;
      if (time <= 0) return;
      final seen = AppSettings.store.getInt(_seenKey) ?? 0;
      if (time <= seen) return;
      await AppSettings.store.setInt(_seenKey, time);
      // Only recent problems (an old crash from before this check existed
      // isn't news).
      final when = DateTime.fromMillisecondsSinceEpoch(time);
      if (DateTime.now().difference(when) > const Duration(days: 2)) return;
      await Future<void>.delayed(const Duration(seconds: 2));
      final ctx =
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final reason = info['reason'] as String? ?? 'crash';
      final report = [
        'Vibe ${VibeAppInfo.version} — $reason',
        'when: $when',
        if ((info['description'] as String? ?? '').isNotEmpty)
          'details: ${info['description']}',
        '',
        info['trace'] as String? ?? '',
      ].join('\n');
      await showVibeDialog<void>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          title: const Text('Vibe closed unexpectedly'),
          content: Text(
            reason == 'not responding'
                ? 'Last time Vibe stopped responding and Android closed it. '
                      'Copy the report and send it to support to help fix it.'
                : 'Last time Vibe crashed and restarted. Copy the report '
                      'and send it to support to help fix it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (dctx.mounted) Navigator.pop(dctx);
                if (ctx.mounted) {
                  ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                    const SnackBar(content: Text('Crash report copied')),
                  );
                }
              },
              child: const Text('Copy report'),
            ),
          ],
        ),
      );
    } catch (e) {
      Logs().v('Vibe crash report: $e');
    }
  }
}
