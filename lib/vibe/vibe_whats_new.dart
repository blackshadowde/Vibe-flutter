// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Release notes. NEWEST FIRST. Add a new entry at the top for every
/// release; `version` is the major.minor from pubspec.yaml (the build
/// number is added automatically by the release workflow).
const vibeReleaseNotes = <({String version, List<(String, String)> items})>[
  (
    version: '2.0',
    items: [
      ('❤️', 'Support Vibe: Settings → Support Vibe has a UPI QR code and UPI ID if you\'d like to donate'),
      ('💭', 'New status look: tap the thought bubble next to your picture in your profile to set a status'),
      ('🔗', 'Link previews: links show a card with title, description and picture. Turn off in Settings → Security & sign-in'),
      ('🚀', 'In-app updates: Vibe tells you when a new version is out and installs it for you. A red dot on the gear means one is waiting; see Settings → Updates'),
      ('💬', 'Chat looks more like Discord: smaller profile pictures, tighter spacing, and today\'s messages show just the time'),
      ('☀️', 'Light mode: names are dark with a soft shadow, easy to read on white'),
      ('👇', 'Swipe down to close your profile and other people\'s profiles'),
      ('↩', 'Smoother replies: no more stutter when you send a reply'),
      ('🔔', 'Built-in notifications: Settings → Notifications → "Built-in, no Google" works without Firebase or extra apps'),
      ('🔒', 'Lock chats: long-press a chat → Lock chat. It hides behind your fingerprint under "Locked chats", and its notifications never show who or what'),
      ('📶', 'Low data mode: Settings → Chat. Photos load only when you tap, GIFs don\'t autoplay, photos you send are smaller'),
      ('⏳', '"Waiting for connection…" on messages typed without signal; they send by themselves when you\'re back online'),
      ('✨', 'Plus everything from 1.1: custom status, their time, disappearing messages, send later, new reactions and more'),
    ],
  ),
  (
    version: '1.1',
    items: [
      ('💭', 'Custom status: tap your name at the bottom to set "On watch", "Busy at work"… with Clear after'),
      ('🕓', 'Their time: see the other person\'s local time in a bubble at the top of the chat'),
      ('⏱', 'Disappearing messages: chat ⋮ menu → pick 1 hour to 90 days'),
      ('🗓', 'Send later: long-press the send button to schedule a message'),
      ('🎉', 'New reaction animations for every emoji, plus the ❤ burst from the menu'),
      ('🖼', 'Media slideshow: swipe through every photo and video of a chat'),
      ('📌', 'Pin chats: long-press a chat to keep it on top'),
      ('📇', 'Share phone contacts as well as Matrix contacts'),
      ('🧑‍🚀', 'Create accounts on servers like Unredacted right inside Vibe'),
      ('🌐', 'Choose your server on the sign-in screen'),
      ('📦', 'Send big files in parts (Vibe to Vibe)'),
      ('💾', 'Save received photos to your gallery and keep media on the phone'),
      ('↩', 'Discord-style swipe to reply, smoother and with a vibration'),
      ('🐞', 'Fixes: unread badges, read receipts, pop-up notifications, haptics, sign-in, and more'),
    ],
  ),
];

abstract class VibeWhatsNew {
  static const _seenKey = 'chat.vibe.whats_new_seen';

  /// Show the card once after every update. Call when the home screen
  /// is up.
  static Future<void> maybeShow() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version; // e.g. 1.1.37
      final seen = AppSettings.store.getString(_seenKey);
      if (seen == version) return;
      await AppSettings.store.setString(_seenKey, version);
      final ctx =
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await show(ctx, version);
    } catch (_) {}
  }

  static Future<void> show(BuildContext context, String version) {
    final short = version.split('.').take(2).join('.');
    final notes =
        vibeReleaseNotes.where((n) => n.version == short).firstOrNull ??
        vibeReleaseNotes.first;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx, scroll) => Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF5865F2), Color(0xFF8C54E8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✨', style: TextStyle(fontSize: 34)),
                      const SizedBox(height: 8),
                      const Text(
                        'What\'s new in Vibe',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Version $version',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (final item in notes.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            item.$1,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.$2,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5865F2),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        'Got it',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
