// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vibe shows its own "What's new" card (lib/vibe/vibe_whats_new.dart), so
/// FluffyChat's update dialog (Support / Changelog links) is gone. This only
/// remembers the installed version.
abstract class UpdateNotifier {
  static const String versionStoreKey = 'last_known_version';

  static Future<void> showUpdateDialog(BuildContext context) async {
    final currentVersion = await PlatformInfos.getVersion();
    final store = await SharedPreferences.getInstance();
    await store.setString(versionStoreKey, currentVersion);
  }
}
