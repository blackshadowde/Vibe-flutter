// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/vibe/vibe_palette.dart';
import 'package:fluffychat/vibe/vibe_dialog.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/vibe/vibe_app_info.dart';
import 'package:fluffychat/vibe/vibe_updater.dart';
import 'package:fluffychat/vibe/vibe_welcome.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher_string.dart';

Color get _blurple => VibePalette.accent;

/// iPhone: updates come through AltStore / SideStore from this source.
const _iosSource =
    'https://raw.githubusercontent.com/blackshadowde/Vibe-flutter/Vibe/altstore.json';

/// About Vibe, laid out like Vibgram's About: logo, name, tagline, version
/// pill, update status, one blurple button and outlined buttons below.
class VibeAboutPage extends StatefulWidget {
  const VibeAboutPage({super.key});

  @override
  State<VibeAboutPage> createState() => _VibeAboutPageState();
}

class _VibeAboutPageState extends State<VibeAboutPage> {
  String _version = VibeAppInfo.version;
  String _status = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    PlatformInfos.getVersion().then((v) {
      if (!mounted) return;
      final clean = v.split(' ').first.split('+').first;
      if (clean.isNotEmpty) setState(() => _version = clean);
      if (PlatformInfos.isIOS) _checkIos();
    }).catchError((_) {});
  }

  /// The newest iPhone build listed in the AltStore / SideStore source.
  Future<void> _checkIos() async {
    try {
      final res = await http.get(Uri.parse(_iosSource));
      final json = jsonDecode(res.body) as Map<String, Object?>;
      final apps = json['apps'] as List;
      final versions = (apps.first as Map)['versions'] as List;
      if (versions.isEmpty) return;
      final latest = (versions.first as Map)['version'] as String;
      if (!mounted) return;
      setState(
        () => _status = VibeUpdater.compare(latest, _version) > 0
            ? 'Vibe $latest is available in AltStore / SideStore'
            : "You're on the latest version",
      );
    } catch (_) {}
  }

  void _openStore(String scheme) => launchUrlString(
    '$scheme://source?url=${Uri.encodeComponent(_iosSource)}',
    mode: LaunchMode.externalApplication,
  );

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = 'Checking…';
    });
    try {
      final r = await VibeUpdater.refresh();
      if (!mounted) return;
      if (r == null) {
        setState(() => _status = "You're on the latest version");
      } else {
        setState(() => _status = 'Vibe ${r.version} is available');
        await VibeUpdater.install(context, r);
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'No connection to GitHub');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Image.asset(
                'assets/logo/mini/logo_mini.png',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 120,
                  height: 120,
                  color: _blurple,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.chat_bubble,
                    size: 54,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            VibeAppInfo.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'A private messenger built on Matrix',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Version $_version  ·  Matrix',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 20,
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ),
          if (PlatformInfos.isAndroid) ...[
            const SizedBox(height: 10),
            _AboutButton(
              text: 'Check for updates',
              filled: true,
              onTap: _check,
            ),
          ],
          if (PlatformInfos.isIOS) ...[
            const SizedBox(height: 10),
            _AboutButton(
              text: 'Get updates in SideStore',
              filled: true,
              onTap: () => _openStore('sidestore'),
            ),
            const SizedBox(height: 10),
            _AboutButton(
              text: 'Get updates in AltStore',
              onTap: () => _openStore('altstore'),
            ),
          ],
          const SizedBox(height: 10),
          _AboutButton(
            text: 'Source code on GitHub',
            onTap: () => launchUrlString(
              VibeAppInfo.githubUrl,
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 10),
          _AboutButton(
            text: 'Credits',
            onTap: () => VibeCreditsSheet.show(context),
          ),
          const SizedBox(height: 10),
          _AboutButton(
            text: 'How Vibe keeps you safe',
            onTap: () => showVibeDialog<void>(
              context: context,
              useSafeArea: false,
              builder: (ctx) => Dialog.fullscreen(
                child: VibeWelcome(onDone: () => Navigator.of(ctx).pop()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Free software based on FluffyChat (GNU AGPL v3).\n'
            'Your messages are end-to-end encrypted and the keys stay on your devices.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vibgram-style button: blurple pill, or outlined pill.
class _AboutButton extends StatelessWidget {
  final String text;
  final bool filled;
  final VoidCallback onTap;

  const _AboutButton({
    required this.text,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: 48,
      child: Material(
        color: filled ? _blurple : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: filled
              ? BorderSide.none
              : BorderSide(color: theme.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: filled ? Colors.white : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Credits: who made Vibe and what it is built on (like Vibgram's Credits).
class VibeCreditsSheet extends StatelessWidget {
  const VibeCreditsSheet({super.key});

  static Future<void> show(BuildContext context) => showVibeSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const VibeCreditsSheet(),
  );

  // name, what it is, licence / note, link (or null)
  static const List<List<String?>> _madeBy = [
    [
      'blackshadowde',
      'Creator of Vibe and Vibgram',
      'Design, features and builds',
      'https://github.com/blackshadowde',
    ],
  ];

  static final List<List<String?>> _team = [
    for (final m in VibeAppInfo.team) [m.name, m.role, null, null],
  ];

  static const List<List<String?>> _builtOn = [
    [
      'FluffyChat',
      'The app Vibe is built on',
      'GNU AGPL v3 · Christian Kußowski and contributors',
      'https://github.com/krille-chan/fluffychat',
    ],
    [
      'Matrix',
      'The open standard Vibe talks over',
      'Apache License 2.0 · The Matrix.org Foundation',
      'https://matrix.org',
    ],
    [
      'Figtree',
      'Typeface',
      'SIL Open Font License 1.1 · The Figtree Project Authors',
      'https://github.com/erikdkennedy/figtree',
    ],
    [
      'Ringtone and sounds',
      'Call and notification sounds',
      'Pixabay',
      'https://pixabay.com',
    ],
    [
      'Noto Animated Emoji',
      'Animated reactions in the message menu',
      'CC BY 4.0 · Google',
      'https://googlefonts.github.io/noto-emoji-animation/',
    ],
    [
      'ntfy',
      'Optional notifications without Google',
      'Apache License 2.0 / GPL v2',
      'https://ntfy.sh',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Credits',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              'The people and projects behind Vibe',
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ),
          ..._section(context, 'MADE BY', _madeBy),
          if (_team.isNotEmpty) ..._section(context, 'TEAM', _team),
          ..._section(context, 'BUILT ON', _builtOn),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
            child: Text(
              'Vibe is free software under the GNU AGPL v3, like FluffyChat. '
              'It is not made by or affiliated with Discord. Tap a card to open its page.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    String label,
    List<List<String?>> rows,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: r[3] == null
                  ? null
                  : () => launchUrlString(
                      r[3]!,
                      mode: LaunchMode.externalApplication,
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r[0] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: r[3] != null ? _blurple : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r[1] ?? '',
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                    if (r[2] != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        r[2]!,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }
}
