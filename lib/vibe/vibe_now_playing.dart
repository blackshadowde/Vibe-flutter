// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/vibe/vibe_status.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Discord-style "Listening to": while a music app plays, your status reads
/// "🎧 Song — Artist"; when it stops, your own status comes back.
/// Android only (needs notification access to see the player).
abstract class VibeNowPlaying {
  static const _channel = MethodChannel('vibe/system');
  static const emoji = '🎧';
  static Client? _client;
  static Timer? _timer;
  static bool _busy = false;

  static bool get supported => PlatformInfos.isAndroid;

  static Future<bool> hasAccess() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasNotificationAccess') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAccess() =>
      _channel.invokeMethod('openNotificationAccess');

  /// Called once per account; follows the first one.
  static void start(Client client) {
    if (!supported) return;
    _client ??= client;
    _restart();
  }

  static Future<void> setEnabled(bool on) async {
    await AppSettings.vibeNowPlaying.setItem(on);
    _restart();
    if (!on) await _restore();
  }

  static void _restart() {
    _timer?.cancel();
    _timer = null;
    if (_client == null || !AppSettings.vibeNowPlaying.value) return;
    poke();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => poke());
  }

  static Future<Map<String, String>?> _now() async {
    try {
      final m = await _channel.invokeMapMethod<String, String>('nowPlaying');
      return m;
    } catch (_) {
      return null;
    }
  }

  static bool get _showing =>
      AppSettings.vibeNowPlayingPrev.value.isNotEmpty;

  /// Check the player now (also every 30 s).
  static Future<void> poke() async {
    final client = _client;
    if (client == null || _busy || !AppSettings.vibeNowPlaying.value) return;
    _busy = true;
    try {
      final np = await _now();
      if (np == null) {
        await _restore();
        return;
      }
      final title = np['title'] ?? '';
      final artist = np['artist'] ?? '';
      final text = artist.isEmpty ? title : '$title — $artist';
      final mine = VibeStatus.mine(client);
      final ours = mine != null && mine.emoji == emoji && mine.active;
      final left = (mine?.untilMs ?? 0) - DateTime.now().millisecondsSinceEpoch;
      // same song and not about to run out: nothing to send
      if (ours && mine.text == text && left > 3 * 60 * 1000) return;
      if (!ours) {
        // remember the status you had, to put it back afterwards
        await AppSettings.vibeNowPlayingPrev.setItem(
          jsonEncode(mine?.toContent() ?? const {}),
        );
      }
      // runs out by itself if Vibe gets closed mid-song
      await VibeStatus.publish(
        client,
        VibeStatus(
          emoji: emoji,
          text: text,
          untilMs: DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
        ),
      );
    } catch (e, s) {
      Logs().w('Now playing status failed', e, s);
    } finally {
      _busy = false;
    }
  }

  static Future<void> _restore() async {
    final client = _client;
    if (client == null || !_showing) return;
    final raw = AppSettings.vibeNowPlayingPrev.value;
    await AppSettings.vibeNowPlayingPrev.setItem('');
    final mine = VibeStatus.mine(client);
    // you changed it yourself meanwhile: keep yours
    if (mine != null && mine.emoji != emoji) return;
    var prev = const VibeStatus();
    try {
      prev = VibeStatus.fromContent(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {}
    if (!prev.active) prev = const VibeStatus();
    await VibeStatus.publish(client, prev);
  }
}
