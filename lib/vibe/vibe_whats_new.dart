// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/widgets/vibe_app.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Release notes. NEWEST FIRST. Add a new entry at the top for every
/// release; `version` is the major.minor from pubspec.yaml (the build
/// number is added automatically by the release workflow).
const vibeReleaseNotes = <({String version, List<String> items})>[
  (
    version: '3.1',
    items: [
      'Sending shows a pulsing dot (a line runs between two dots while it encrypts), then 1 dot sent, 2 dots delivered, 3 blue dots read',
      'Questions, menus and settings pages slide up from the bottom and close with a swipe down',
      'Full-screen effects for words like love, miss you, good morning, good night, hug, kiss, congrats, bye, sweet dreams, hi and welcome',
      'Back up chats to Google Drive automatically: Settings, Backups, Back up to Google Drive',
      'Your profile pane looks like Vibe X: your picture blurred behind it, a floating bar and a smaller thought bubble',
      'Connecting shows three dots in the chat bar that turn green once you\'re connected',
      'Continue with Google, and your password manager fills in your login',
      'New messages glide into the chat, and chats slide open and closed more smoothly',
      'Bold names in the chat list, unread in white, and a red "read up to here" line',
      'Long messages keep their dots right after the text',
      'The media pane shows all the photos and videos in the chat',
    ],
  ),
  (
    version: '3.0',
    items: [
      'Save received photos to your gallery and keep media on the phone',
      'Discord-style swipe to reply, smoother and with a vibration',
      'Fixes: unread badges, read receipts, pop-up notifications, haptics, sign-in, and more',
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
          VibeApp.router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await show(ctx, version);
    } catch (_) {}
  }

  /// Vibe X's card: the logo, the title, one dot per change (each pops in,
  /// one after another) and a round "Got it".
  static Future<void> show(BuildContext context, String version) async {
    final short = version.split('.').take(2).join('.');
    final notes =
        vibeReleaseNotes.where((n) => n.version == short).firstOrNull ??
        vibeReleaseNotes.first;
    // this version's own notes from its release page (what really changed);
    // the list built into the app only if that can't be reached
    var items = notes.items;
    final fetched = await VibeUpdater.notesFor(version).timeout(
      const Duration(seconds: 6),
      onTimeout: () => const <String>[],
    );
    if (fetched.isNotEmpty) items = fetched;
    if (!context.mounted) return;
    VibeHaptics.medium();
    return showVibeSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/logo/mini/logo_mini.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 48,
                            height: 48,
                            color: _blurple,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What\'s new in Vibe',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'You\'re now on $version',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final (i, line) in items.indexed)
                    _PopIn(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 7),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _blurple,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 20 / 15,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Material(
                    color: _blurple,
                    borderRadius: BorderRadius.circular(25),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            'Got it',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Color get _blurple => VibePalette.accent;

/// Vibe X's pop-in: each line springs up from nothing (a little squeeze
/// past full size), 28 ms after the one before.
class _PopIn extends StatefulWidget {
  final int index;
  final Widget child;
  const _PopIn({required this.index, required this.child});

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * 28), () {
      if (!mounted) return;
      _c.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 420,
            ratio: 0.45,
          ),
          0,
          1,
          0,
        ),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: v, child: child),
      );
    },
  );
}

/// One change in Vibe X's style: a blue dot and the text (any emoji at the
/// start is dropped), popping in [index] lines after the first.
class VibeNoteLine extends StatelessWidget {
  final int index;
  final String text;
  const VibeNoteLine({required this.index, required this.text, super.key});

  static final _lead = RegExp(r'^[^\p{L}\p{N}"(]+', unicode: true);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _PopIn(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _blurple,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text.replaceFirst(_lead, ''),
                style: TextStyle(
                  fontSize: 15,
                  height: 20 / 15,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
