// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart';
import 'package:fluffychat/vibe/vibe_support.dart';
import 'package:fluffychat/vibe/vibe_updater.dart';
import 'package:fluffychat/vibe/vibe_updates_page.dart';
import 'package:async/async.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
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
      sheetAnimationStyle: vibeSheetStyle,
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
      sheetAnimationStyle: vibeSheetStyle,
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
    final backupOk = controller.cryptoIdentityConnected == true;

    // Vibgram's Discord-style settings: title on the line of the close
    // button, grey group titles, rounded cards with filled icons.
    return VibeSettingsTheme(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => context.go('/rooms'),
            ),
            titleSpacing: 4,
            title: Text(
              L10n.of(context).settings,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          body: ListView(
            key: const Key('SettingsListViewContent'),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              VibeSettingsGroup(
                title: 'Account Settings',
                rows: [
                  FutureBuilder<Profile>(
                    future: controller.profileFuture,
                    builder: (context, snapshot) {
                      final mxid =
                          Matrix.of(context).client.userID ??
                          L10n.of(context).user;
                      final name =
                          snapshot.data?.displayName ?? mxid.localpart ?? mxid;
                      return VibeSettingsRow(
                        icon: Icons.person,
                        title: 'Account',
                        value: name,
                        onTap: () => _accountSheet(context),
                      );
                    },
                  ),
                  VibeSettingsRow(
                    icon: Icons.shield,
                    title: 'Security & sign-in',
                    onTap: () => context.go('/rooms/settings/security'),
                  ),
                  VibeSettingsRow(
                    icon: Icons.lock,
                    title: 'Encryption & Keys',
                    value: backupOk ? 'Active' : 'Not set up',
                    valueColor: backupOk
                        ? null
                        : const Color(0xFFF23F43),
                    onTap: () =>
                        context.go('/rooms/settings/vibe-encryption'),
                  ),
                  VibeSettingsRow(
                    icon: Icons.devices,
                    title: 'Account management',
                    last: true,
                    onTap: () => _managementSheet(context),
                  ),
                ],
              ),
              VibeSettingsGroup(
                title: 'App Settings',
                rows: [
                  VibeSettingsRow(
                    icon: Icons.notifications,
                    title: 'Notifications',
                    onTap: () => context.go('/rooms/settings/notifications'),
                  ),
                  VibeSettingsRow(
                    icon: Icons.palette,
                    title: 'Appearance',
                    onTap: () => context.go('/rooms/settings/style'),
                  ),
                  VibeSettingsRow(
                    icon: Icons.chat_bubble,
                    title: 'Chats & storage',
                    last: true,
                    onTap: () => context.go('/rooms/settings/chat'),
                  ),
                ],
              ),
              VibeSettingsGroup(
                title: 'Support',
                rows: [
                  ValueListenableBuilder<VibeRelease?>(
                    valueListenable: VibeUpdater.pending,
                    builder: (context, update, _) => VibeSettingsRow(
                      icon: Icons.system_update,
                      title: 'Updates',
                      value: update == null ? null : 'Update ready',
                      valueColor: const Color(0xFFF23F43),
                      onTap: () => VibeUpdatesPage.open(context),
                    ),
                  ),
                  VibeSettingsRow(
                    icon: Icons.favorite,
                    title: 'Support Vibe',
                    onTap: () => VibeSupport.open(context),
                  ),
                  VibeSettingsRow(
                    icon: Icons.info,
                    title: 'About Vibe',
                    last: true,
                    onTap: () => context.go('/rooms/settings/vibe-about'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
