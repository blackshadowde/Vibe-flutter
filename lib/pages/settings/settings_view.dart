// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/vibe/vibe_about_page.dart';
import 'package:fluffychat/vibe/vibe_encryption_page.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'settings.dart';

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  void _accountSheet(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: FutureBuilder<Profile>(
          future: controller.profileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final mxid =
                Matrix.of(context).client.userID ?? L10n.of(context).user;
            final displayname = profile?.displayName ?? mxid.localpart ?? mxid;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Avatar(
                    mxContent: profile?.avatarUrl,
                    name: displayname,
                    size: 96,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayname,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () => FluffyShare.share(mxid, context),
                    child: Text(mxid),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Change profile photo'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      controller.setAvatarAction();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(L10n.of(context).editDisplayname),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      controller.setDisplaynameAction();
                    },
                  ),
                  FutureBuilder(
                    future: Result.capture(
                      Matrix.of(context).client.getAuthMetadata(),
                    ).then((result) => result.asValue?.value),
                    builder: (context, snapshot) {
                      final url = snapshot.data?.accountManagementUri;
                      if (url == null) return const SizedBox.shrink();
                      return ListTile(
                        leading: const Icon(Icons.open_in_new_outlined),
                        title: Text(L10n.of(context).manageAccount),
                        onTap: () => launchUrl(
                          url,
                          mode: LaunchMode.inAppBrowserView,
                        ),
                      );
                    },
                  ),
                  Divider(color: theme.dividerColor),
                  ListTile(
                    leading: const Icon(Icons.logout_outlined),
                    title: Text(L10n.of(context).logout),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      controller.logoutAction();
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _managementSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text(L10n.of(context).devices),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.go('/rooms/settings/devices');
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(
                L10n.of(context).aboutHomeserver(
                  Matrix.of(context).client.userID?.domain ?? 'homeserver',
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.go('/rooms/settings/homeserver');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(L10n.of(context).privacy),
              onTap: () => launchUrlString(AppSettings.privacyPolicy.value),
            ),
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: Text(L10n.of(context).logout),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.logoutAction();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final backupOk = controller.cryptoIdentityConnected == true;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          L10n.of(context).settings,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.go('/rooms'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        key: const Key('SettingsListViewContent'),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              'Settings',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: Text(
              'Manage your Vibe account & preferences',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ),
          FutureBuilder<Profile>(
            future: controller.profileFuture,
            builder: (context, snapshot) {
              final mxid =
                  Matrix.of(context).client.userID ?? L10n.of(context).user;
              final name = snapshot.data?.displayName ?? mxid.localpart ?? mxid;
              return _SettingsCard(
                icon: Icons.person,
                title: 'Account',
                subtitle: name,
                onTap: () => _accountSheet(context),
              );
            },
          ),
          _SettingsCard(
            icon: Icons.verified_user_outlined,
            title: 'Security & sign-in',
            subtitle: 'Password, active sessions & sign-in',
            onTap: () => context.go('/rooms/settings/security'),
          ),
          _SettingsCard(
            icon: Icons.lock,
            title: 'Encryption & Keys',
            subtitle: 'End-to-end encryption status',
            badge: backupOk ? 'Active' : 'Not set up',
            badgeColor: backupOk
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VibeEncryptionPage()),
            ),
          ),
          _SettingsCard(
            icon: Icons.notifications,
            title: 'Notifications',
            subtitle: 'In-app alerts & push notifications',
            onTap: () => context.go('/rooms/settings/notifications'),
          ),
          _SettingsCard(
            icon: Icons.contrast,
            title: 'Appearance',
            subtitle: 'Dark/light mode, font size & haptics',
            onTap: () => context.go('/rooms/settings/style'),
          ),
          _SettingsCard(
            icon: Icons.folder,
            title: 'Chats & storage',
            subtitle: 'Media downloads & link previews',
            onTap: () => context.go('/rooms/settings/chat'),
          ),
          _SettingsCard(
            icon: Icons.info,
            title: 'About Vibe',
            subtitle: 'App version & information',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VibeAboutPage()),
            ),
          ),
          _SettingsCard(
            icon: Icons.delete,
            iconColor: Colors.redAccent,
            title: 'Account management',
            subtitle: 'Devices, homeserver & log out',
            onTap: () => _managementSheet(context),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: theme.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainerHighest,
                  ),
                  child: Icon(icon, color: iconColor ?? cs.onSurface, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? cs.primary).withAlpha(40),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (badgeColor ?? cs.primary).withAlpha(140),
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: badgeColor ?? cs.primary,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
