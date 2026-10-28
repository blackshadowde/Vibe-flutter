// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/universal_html.dart' as web;
import 'package:vibe/config/setting_keys.dart';

/// Web only, optional: "Log out when the browser closes", for shared
/// computers. The browser forgets session storage when it closes, so a start
/// without our mark means the browser was closed since: sign out then.
abstract class VibeWebSession {
  static const _mark = 'vibe_session_alive';

  static Future<void> check(List<Client> clients) async {
    if (!kIsWeb) return;
    bool alive;
    try {
      alive = web.window.sessionStorage[_mark] == '1';
      web.window.sessionStorage[_mark] = '1';
    } catch (_) {
      return;
    }
    if (alive || !AppSettings.vibeWebSessionOnly.value) return;
    for (final client in clients) {
      if (!client.isLogged()) continue;
      Logs().i('Browser was closed: logging out ${client.userID}');
      try {
        await client.logout();
      } catch (e) {
        // offline: at least wipe what this browser keeps
        try {
          await client.clear();
        } catch (_) {}
      }
    }
  }
}
