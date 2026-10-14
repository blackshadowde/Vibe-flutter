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
    version: '3.1',
    items: [
      ('⚡', 'Calls are now built into Vibe itself instead of running a web page inside the app: they connect faster, use less battery, and the audio is cleaner'),
      ('🖥', 'Share your screen in a call: tap Share. Android asks once, then everyone in the call sees your screen (Element and Element X too)'),
      ('🔁', 'Video calls: tap your small video to swap it with theirs, like WhatsApp. Flip between front and back camera with the camera button at the top'),
      ('👥', 'Group video calls show everyone in a grid, with a green ring around whoever is talking'),
      ('🔒', 'Calls stay end-to-end encrypted and still work with Element, Element X and Sable'),
      ('📵', 'An unanswered or declined call ends by itself'),
      ('🌙', 'The app icon follows your phone: white with the blue bubble in light mode, blue with a white bubble and padlock in dark mode. With themed icons (Material You) on, it takes your wallpaper colours'),
      ('👀', 'While you\'re in a chat, someone else typing or writing to you no longer pops up a notification: their picture peeks in from the side above the typing bar (dots while they type). Tap it to jump to their chat, swipe it right to dismiss'),
      ('🔔', 'No more double notifications: Google Firebase is gone, Vibe\'s own connection delivers everything (Settings → Notifications)'),
      ('📹', 'Your camera now reaches the other person when you start the call'),
      ('📴', 'Hanging up while a call is still connecting really ends it, and a declined call stops ringing them'),
      ('🗑', 'Delete chat now always removes the chat from your phone, even ones the server no longer knows about'),
      ('📹', 'Their camera now shows up when they turn it on during a call'),
      ('😀', 'Call reactions float up the screen in video calls too'),
    ],
  ),
  (
    version: '3.0',
    items: [
      ('📞', 'Voice and video calls! Open a chat\'s pane and tap # | audio-call or # | video-call. End-to-end encrypted, and they work with people on Sable, Element and Element X'),
      ('😀', 'React during a call: tap the smiley at the top and pick an emoji. It floats up the screen for everyone (Element shows it too). The hand button raises your hand'),
      ('🔁', 'Video calls: tap your own small video to make it big and theirs small, like WhatsApp. Tap again to switch back'),
      ('📴', 'Calls end properly: hanging up (or the other person leaving a one-to-one call) no longer leaves a "call running" in the chat. Old stuck calls are cleared when Vibe starts'),
      ('💬', 'Calling or messaging someone from their profile opens your existing chat with them instead of making a second, unencrypted one. New chats are always encrypted'),
      ('📌', 'Long-press a picture in the left rail works again (Pin, Mute, Archive), and now has Delete chat'),
      ('🧹', 'Empty unencrypted duplicate chats that older versions made after a call are removed automatically'),
      ('🔤', 'Settings pages and buttons now use the same font as the rest of Vibe'),
      ('📱', 'A proper call screen: big picture, timer, and Speaker · Camera · Mute · End buttons. Tap the grid button to see video'),
      ('🔊', 'Voice chats for groups: tap # | voice in the group pane, or the green "Join" when one is live. You see who\'s in it before you join'),
      ('🎧', 'Voice channels in communities: + → Voice. Hop in and out like Discord; the rail shows a green speaker where people are talking'),
      ('🔒', 'The chat\'s lock is now top right and shows how safe the chat is: green = verified, amber = a device isn\'t verified, red = not encrypted. Search moved into the ⋮ menu'),
      ('🪶', 'Lighter, cleaner screens: profiles (with Member since and quick call buttons), sign-in, choosing a server, the encryption page and every settings page'),
      ('🔤', 'New look for text: Figtree, a friendly rounded typeface, and the new Vibe icon everywhere'),
      ('🕑', 'Their time shows just the time now'),
      ('🩹', 'If Vibe ever closes unexpectedly, it tells you next time and lets you copy a report'),
      ('⬇', 'Keep using Vibe during a call: tap the arrow and the call shrinks to a green bar at the top. Mute, hang up or jump back in from there'),
      ('🔔', 'Incoming calls ring full screen, even from the lock screen. Answer or decline in one tap'),
      ('🎙', 'Deafen (hear nobody), earpiece or loudspeaker, camera on or off, all during the call'),
      ('✨', 'Send with effects plays after your message has slid in, and fills the whole chat above the keyboard'),
      ('ℹ', 'Starting a call needs a server with Matrix calls (matrix.org has them); Vibe tells you if yours doesn\'t. You can always join calls others start. FluffyChat uses an older call system that doesn\'t work with these calls'),
    ],
  ),
  (
    version: '2.2',
    items: [
      ('🏘', 'Communities: tap + in the rail → Create community. Several channels (# | general, …) in one place, like a server. Communities sit at the bottom of the rail with an unread badge; add channels with + or add groups you already have'),
      ('🌐', 'Public groups: make a group or community public with its own #link, or find and join public ones: + → Find public groups'),
      ('🖼', 'Group pictures: # | group-picture in the group pane, or long-press the group\'s picture'),
      ('🛡', 'Admins: open members and long-press someone to make them an admin or moderator, demote them, or remove them'),
      ('@', '@mentions: type @ in a group and pick someone from the list'),
      ('🔕', 'Hide the permanent "Connected for notifications" notification: Settings → Notifications → Hide the permanent notification. Vibe stays connected and messages still arrive'),
      ('👥', 'Groups: tap + in the left rail → Create group. Groups sit under your DMs in the rail; their pane has # | chat, media, files, links, members, invite-people (by ID or link), rename and leave. End-to-end encrypted'),
      ('📌', 'Long-press a picture in the left rail: Pin, Mute or Archive the chat with one tap'),
      ('🗄️', 'Archived chats are hidden; long-press your own picture at the top of the rail to open them. A chat comes back while it has new messages (unless muted)'),
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
