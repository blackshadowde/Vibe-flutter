// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Release notes. NEWEST FIRST. Add a new entry at the top for every
/// release; `version` is the major.minor from pubspec.yaml (the build
/// number is added automatically by the release workflow).
const vibeReleaseNotes = <({String version, List<(String, String)> items})>[
  (
    version: '2.2',
    items: [
      ('✨', 'Motion like Apple\'s fluid interfaces: panes and pages move on springs, a flick keeps its speed when you close a chat, and you can grab a page while it\'s still sliding in'),
      ('🔠', 'Text size like Telegram: Settings → Style, 12 to 30 (16 is normal). Only message text changes; names and times stay the same. The preview now looks exactly like your chats'),
      ('🖼️', 'Tap a photo or video in a chat for a Google Messages style slideshow of the whole chat; long-press one to jump to it. The download button saves straight to your gallery'),
      ('🪟', 'Panes slide up smoother everywhere: quicker Telegram-like timing, and heavy content (pictures, emoji, animations) appears right after the pane has opened instead of during the slide'),
      ('✉️', 'Sending feels calm: a message slides in once, then only the word after it changes: Encrypting… → ✓ → blue ✓✓. No more second animation or jump when it\'s confirmed'),
      ('💾', 'Storage & cache (Settings → Chat): choose how much space media may use (1 GB up to no limit), how long to keep it, and how much memory Vibe uses for smooth scrolling. Clear the cache any time'),
      ('#️⃣', 'New chat pane like Vibgram: big picture, online, # | chat and INFO channels (media, files, links, voice-messages, starred-messages, profile). Each opens its own pane from the bottom: tap to open, long-press to see it in the chat. Media opens a full-screen slideshow, and nothing reloads when you come back'),
      ('🧈', 'Smoother everywhere: pages slide over with the page below drifting back (like Telegram), new messages and lists animate without redrawing the whole screen, scrolling no longer squeezes the row under your finger, and the home screen only refreshes when something changes'),
      ('👋', 'New start screen: create your account right in Vibe (on Unredacted by default, confirmed by email). Already have one? Tap Log in'),
      ('🖼️', 'Profile pictures like Vibgram: grey with initials when there\'s no picture, round everywhere, rounded squares in the left rail'),
      ('🎉', 'Send with effects: type a message, long-press the send button and pick Like, Love, Fire, Party, LOL, Dislike, Poop or Balloons. It plays for you and for them, and the small emoji next to the message plays it again'),
      ('😂', 'Animated emoji: a message that is just one emoji is shown big and animated, each emoji with its own animation. Tap it for a burst'),
      ('🔍', 'Search emoji when reacting: long-press a message, tap the smiley and type to find any emoji'),
      ('🎨', 'Emoji picker in Vibe colours, with your favourites animated at the top'),
      ('🕐', 'Status and local time fixed: new contacts see them right away, they stay the same on all your devices, and their profile always shows their time (or "same time as you")'),
    ],
  ),
  (
    version: '2.1',
    items: [
      ('🔔', 'Notifications like Vibgram: Vibe stays connected and shows messages the moment they arrive. Settings → Notifications → Direct connection'),
      ('💾', 'Chat backups: save every chat to a password-locked file on your phone or Google Drive, and open it any time to read old chats. Settings → Backups'),
      ('🔁', 'Automatic backups every day or week, kept in Downloads/Vibe backups even if Vibe is uninstalled'),
      ('🙈', 'Status privacy: choose who sees your status and local time (everyone, people you pick, or nobody). Settings → Security & sign-in'),
      ('👻', 'Hide online and last seen: nobody sees when you\'re online or were last active'),
      ('⚙️', 'New Settings look: rounded cards, filled icons and the same calm colours on every page'),
      ('😂', 'Animated emojis in the message menu'),
      ('✍️', 'New typing indicator: their picture and three bouncing dots, right above the message box'),
      ('#️⃣', 'Middle pane: # | media, # | links, # | files and # | starred-messages'),
      ('⌨️', 'Roomier message box: "# Message | name" fits, and the camera moved into the + menu'),
      ('ℹ️', 'A cleaner About page and a new Credits page'),
    ],
  ),
  (
    version: '2.0',
    items: [
      ('🔔', 'Built-in notifications (no Google) now actually work. If you use them, just open Vibe once after updating'),
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
    return showVibeSheet<void>(
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
