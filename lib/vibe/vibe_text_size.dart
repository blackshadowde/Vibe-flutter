// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';

/// Chat text size, the Telegram way: a size from 12 to 30 (default 16)
/// that sets the size of message text. Names (16) and times (12) stay the
/// same, like Telegram / Vibgram. As in Vibgram, Vibe's timeline text is
/// drawn one point larger than the chosen size.
abstract class VibeTextSize {
  static const int min = 12;
  static const int max = 30;
  static const int normal = 16;

  /// The chosen size (12–30). Older Vibe versions stored a multiplier;
  /// that is converted the first time.
  static int get value {
    final v = AppSettings.vibeTextSize.value;
    if (v >= min && v <= max) return v;
    return (normal * AppSettings.fontSizeFactor.value).round().clamp(min, max);
  }

  static Future<void> set(int v) =>
      AppSettings.vibeTextSize.setItem(v.clamp(min, max));

  /// Font size of message text in chats.
  static double get message => (value + 1).toDouble();
}
