// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/vibe/vibe_app_info.dart';
import 'package:fluffychat/vibe/vibe_updates_page.dart';
import 'package:fluffychat/vibe/vibe_welcome.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class VibeAboutPage extends StatefulWidget {
  const VibeAboutPage({super.key});

  @override
  State<VibeAboutPage> createState() => _VibeAboutPageState();
}

class _VibeAboutPageState extends State<VibeAboutPage> {
  String _version = VibeAppInfo.version;

  @override
  void initState() {
    super.initState();
    PlatformInfos.getVersion().then((v) {
      if (!mounted) return;
      final clean = v.split(' ').first.split('+').first;
      if (clean.isNotEmpty) setState(() => _version = clean);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text(
          'About',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SizedBox(height: 12),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/logo/mini/logo_mini.png',
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 96,
                  height: 96,
                  color: cs.primary,
                  alignment: Alignment.center,
                  child: Icon(Icons.chat_bubble, size: 44, color: cs.onPrimary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              VibeAppInfo.name,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'Version $_version',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC9CFFF),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'A private messenger built on Matrix. Your messages are '
              'end-to-end encrypted, and the keys stay on your devices.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (PlatformInfos.isAndroid) ...[
            _AboutCard(
              icon: Icons.system_update_alt,
              title: 'Check for updates',
              sub: 'Get the newest Vibe from GitHub',
              trailing: Icons.chevron_right,
              onTap: () => VibeUpdatesPage.open(context),
            ),
            const SizedBox(height: 12),
          ],
          _AboutCard(
            icon: Icons.shield_outlined,
            title: 'How Vibe keeps you safe',
            sub: 'Replay the welcome tour',
            trailing: Icons.chevron_right,
            onTap: () => showDialog<void>(
              context: context,
              useSafeArea: false,
              builder: (ctx) => Dialog.fullscreen(
                child: VibeWelcome(onDone: () => Navigator.of(ctx).pop()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AboutCard(
            icon: Icons.code,
            title: 'Source code on GitHub',
            sub: VibeAppInfo.githubUrl.replaceFirst('https://', ''),
            extra: VibeAppInfo.githubOwner,
            trailing: Icons.open_in_new,
            onTap: () => launchUrlString(
              VibeAppInfo.githubUrl,
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDeco(cs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THE TEAM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final m in VibeAppInfo.team)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: cs.primary,
                          child: Text(
                            _initials(m.name),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              m.role,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Built on the Matrix open standard',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '© ${DateTime.now().year} ${VibeAppInfo.name}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final letters = name.replaceAll(RegExp(r'[^A-Za-z ]'), ' ').trim();
    final parts = letters.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

BoxDecoration _cardDeco(ColorScheme cs) => BoxDecoration(
  color: cs.surfaceContainerHigh,
  borderRadius: BorderRadius.circular(24),
  border: Border.all(color: cs.outlineVariant),
);

class _AboutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final String? extra;
  final IconData trailing;
  final VoidCallback onTap;

  const _AboutCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.trailing,
    required this.onTap,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: _cardDeco(cs),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 22, color: const Color(0xFFC9CFFF)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (extra != null)
                      Text(
                        extra!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'RobotoMono',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(trailing, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
