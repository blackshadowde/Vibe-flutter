// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';

/// Local (on-device) starred messages, stored per room.
abstract class VibeStarred {
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static String _key(String roomId) => 'vibe.starred.$roomId';

  static List<String> ids(String roomId) =>
      AppSettings.store.getStringList(_key(roomId)) ?? const [];

  static bool isStarred(String roomId, String eventId) =>
      ids(roomId).contains(eventId);

  static Future<void> toggle(String roomId, String eventId) async {
    final list = List<String>.of(ids(roomId));
    if (!list.remove(eventId)) list.insert(0, eventId);
    await AppSettings.store.setStringList(_key(roomId), list);
    revision.value++;
  }
}
