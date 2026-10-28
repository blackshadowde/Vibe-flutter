// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:vibe/widgets/app_lock.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_privacy.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/utils/beautify_string_extension.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/settings_switch_list_tile.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

final _accountPages = Expando<Future<Uri?>>();

/// The server's account page, or null when the server has none.
Future<Uri?> _accountPage(Client client) => _accountPages[client] ??= client
    .getAuthMetadata()
    .then<Uri?>((m) => m.accountManagementUri)
    .catchError((_) => null);

class VibeSecurityPage extends StatefulWidget {
  const VibeSecurityPage({super.key});

  @override
  _VibeSecurityPageState createState() => _VibeSecurityPageState();
}

class _VibeSecurityPageState extends State<VibeSecurityPage> {
  Future<void> toggleBiometrics() async {
    AppLock.of(context).showLockScreen();

    final oldState = AppLock.of(context).useBiometrics;
    final actionStr = oldState
        ? L10n.of(context).disableBiometrics
        : L10n.of(context).enableBiometrics;
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: actionStr,
      message: L10n.of(context).biometricsDescription,
      okLabel: actionStr,
      cancelLabel: L10n.of(context).cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;

    if (!oldState) {
      final localAuth = LocalAuthentication();
      final unlocked = await localAuth.authenticate(
        localizedReason: actionStr,
        biometricOnly: true,
      );
      if (!unlocked) return;
      if (!mounted) return;
    }
    await AppLock.of(context).changeUseBiometrics(!oldState);
    setState(() {});
  }

  Future<void> disableAppLockAction() async {
    AppLock.of(context).showLockScreen();
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).disableAppLock,
      message: L10n.of(context).disableAppLockAreYouSure,
      okLabel: L10n.of(context).disableAppLock,
      cancelLabel: L10n.of(context).cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok) return;
    if (!mounted) return;
    await AppLock.of(context).changePincode(null);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> setAppLockAction() async {
    await AppLock.of(context).changeUseBiometrics(false);
    if (!mounted) return;
    final l10n = L10n.of(context);
    if (AppLock.of(context).isActive) {
      AppLock.of(context).showLockScreen();
    }
    final newLock = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.pleaseChooseAPasscode,
      message: l10n.pleaseEnter6Digits,
      cancelLabel: l10n.cancel,
      validator: (text) {
        if (text.length == 6 && int.tryParse(text)! >= 0) {
          return null;
        }
        return l10n.pleaseEnter6Digits;
      },
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLines: 1,
      minLines: 1,
      maxLength: 6,
    );
    if (newLock != null) {
      if (!mounted) return;
      await AppLock.of(context).changePincode(newLock);
      setState(() {});
    }
  }

  Future<void> deleteAccountAction() async {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: l10n.warning,
          message: l10n.deactivateAccountWarning,
          okLabel: l10n.ok,
          cancelLabel: l10n.cancel,
          isDestructive: true,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    if (!mounted) return;
    final supposedMxid = matrix.client.userID!;
    final mxid = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.confirmMatrixId,
      validator: (text) =>
          text == supposedMxid ? null : l10n.supposedMxid(supposedMxid),
      isDestructive: true,
      okLabel: l10n.delete,
      cancelLabel: l10n.cancel,
    );
    if (mxid == null || mxid.isEmpty || mxid != supposedMxid) {
      return;
    }
    if (!mounted) return;
    final resp = await showFutureLoadingDialog(
      context: context,
      delay: false,
      future: () => matrix.client.uiaRequestBackground<IdServerUnbindResult?>(
        (auth) => matrix.client.deactivateAccount(auth: auth, erase: true),
      ),
    );

    if (!resp.isError) {
      if (!mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.logout(),
      );
    }
  }

  Future<void> dehydrateAction() => Matrix.of(context).dehydrateAction(context);

  Future<void> changeShareKeysWith(ShareKeysWith? shareKeysWith) async {
    if (shareKeysWith == null) return;
    AppSettings.shareKeysWith.setItem(shareKeysWith.name);
    Matrix.of(context).client.shareKeysWith = shareKeysWith;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final publicMasterKey =
        client.userDeviceKeys[client.userID]?.masterKey?.publicKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).security),
        automaticallyImplyLeading: !VibeThemes.isColumnMode(context),
        centerTitle: VibeThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: MaxWidthBody(
          child: FutureBuilder(
            future: Matrix.of(
              context,
            ).client.getCapabilities().timeout(const Duration(seconds: 10)),
            builder: (context, snapshot) {
              final capabilities = snapshot.data;
              final error = snapshot.error;
              if (error == null && capabilities == null) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                );
              }
              return VibeGroups(
                children: [
                  ListTile(
                    title: Text(
                      L10n.of(context).privacy,
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SettingsSwitchListTile.adaptive(
                    title: L10n.of(context).sendTypingNotifications,
                    subtitle: L10n.of(
                      context,
                    ).sendTypingNotificationsDescription,
                    setting: AppSettings.sendTypingNotifications,
                  ),
                  SettingsSwitchListTile.adaptive(
                    title: L10n.of(context).sendReadReceipts,
                    subtitle: L10n.of(context).sendReadReceiptsDescription,
                    setting: AppSettings.sendPublicReadReceipts,
                  ),
                  SettingsSwitchListTile.adaptive(
                    title: 'Link previews',
                    subtitle:
                        'Show a card with title and picture under links. '
                        'Your server fetches the page, so it can see which '
                        'links are shared in your chats.',
                    setting: AppSettings.vibeLinkPreviews,
                  ),
                  SettingsSwitchListTile.adaptive(
                    title: 'Link previews in encrypted chats',
                    subtitle:
                        'Off: your server never sees links from encrypted '
                        'chats. On: it fetches them for the preview card.',
                    setting: AppSettings.vibeLinkPreviewsEncrypted,
                  ),
                  if (kIsWeb)
                    SettingsSwitchListTile.adaptive(
                      title: 'Log out when the browser closes',
                      subtitle:
                          'For shared computers: closing the browser signs '
                          'you out and removes your chats from it.',
                      setting: AppSettings.vibeWebSessionOnly,
                    ),
                  const VibePrivacyTiles(),
                  ListTile(
                    trailing: const Icon(Icons.chevron_right_outlined),
                    title: Text(L10n.of(context).blockedUsers),
                    subtitle: Text(
                      L10n.of(context).thereAreCountUsersBlocked(
                        Matrix.of(context).client.ignoredUsers.length,
                      ),
                    ),
                    onTap: () =>
                        context.go('/rooms/settings/security/ignorelist'),
                  ),
                  if (PlatformInfos.supportsAppLock) ...[
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: Text(
                        L10n.of(context).appLock,
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(L10n.of(context).appLockDescription),
                    ),
                    SwitchListTile.adaptive(
                      value: AppLock.of(context).isActive,
                      title: Text(L10n.of(context).useAppLock),
                      onChanged: (active) => active
                          ? setAppLockAction()
                          : disableAppLockAction(),
                    ),
                    if (AppLock.of(context).isActive) ...[
                      FutureBuilder(
                        future: LocalAuthentication().canCheckBiometrics,
                        builder: (context, snapshot) {
                          if (snapshot.data != true) return SizedBox.shrink();
                          return SwitchListTile.adaptive(
                            value: AppLock.of(context).useBiometrics,
                            onChanged: (_) => toggleBiometrics(),
                            title: Text(L10n.of(context).unlockWithBiometrics),
                          );
                        },
                      ),
                      ListTile(
                        trailing: const Icon(Icons.lock_reset_outlined),
                        title: Text(L10n.of(context).resetPin),
                        onTap: setAppLockAction,
                      ),
                    ],
                  ],

                  Divider(color: theme.dividerColor),
                  ListTile(
                    title: Text(
                      L10n.of(context).shareKeysWith,
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(L10n.of(context).shareKeysWithDescription),
                  ),
                  ListTile(
                    title: Material(
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius / 2,
                      ),
                      color: theme.colorScheme.onInverseSurface,
                      child: DropdownButton<ShareKeysWith>(
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius / 2,
                        ),
                        underline: const SizedBox.shrink(),
                        value: Matrix.of(context).client.shareKeysWith,
                        items: ShareKeysWith.values
                            .map(
                              (share) => DropdownMenuItem(
                                value: share,
                                child: Text(share.localized(L10n.of(context))),
                              ),
                            )
                            .toList(),
                        onChanged: changeShareKeysWith,
                      ),
                    ),
                  ),
                  Divider(color: theme.dividerColor),
                  ListTile(
                    title: Text(
                      L10n.of(context).account,
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (publicMasterKey != null)
                    ListTile(
                      title: Text(L10n.of(context).yourPublicKey),
                      leading: const Icon(Icons.verified_user_outlined),
                      subtitle: SelectableText(
                        publicMasterKey.beautified,
                        style: const TextStyle(fontFamily: 'RobotoMono'),
                      ),
                    ),
                  ListTile(
                    title: Text(L10n.of(context).deviceIdentityKey),
                    leading: const Icon(Icons.mobile_friendly_outlined),
                    subtitle: SelectableText(
                      Matrix.of(context).client.fingerprintKey.beautified,
                      style: const TextStyle(fontFamily: 'RobotoMono'),
                    ),
                  ),
                  // Servers with an account page (matrix.org and others
                  // using Matrix Authentication Service) manage password and
                  // email there; the in-app pages can't change them.
                  FutureBuilder<Uri?>(
                    future: _accountPage(Matrix.of(context).client),
                    builder: (context, snap) {
                      final url = snap.data;
                      if (url != null) {
                        return ListTile(
                          leading: const Icon(Icons.password_outlined),
                          trailing: const Icon(Icons.open_in_new_outlined),
                          title: const Text('Password and email'),
                          subtitle: const Text(
                            'Managed on your server\'s account page',
                          ),
                          onTap: () => launchUrl(
                            url,
                            mode: LaunchMode.inAppBrowserView,
                          ),
                        );
                      }
                      if (snap.connectionState != ConnectionState.done ||
                          (capabilities?.mChangePassword?.enabled == false &&
                              error == null)) {
                        return const SizedBox.shrink();
                      }
                      return ListTile(
                        leading: const Icon(Icons.password_outlined),
                        trailing: const Icon(Icons.chevron_right_outlined),
                        title: Text(L10n.of(context).changePassword),
                        onTap: () =>
                            context.go('/rooms/settings/security/password'),
                      );
                    },
                  ),
                  Divider(color: theme.dividerColor),
                  ListTile(
                    iconColor: Color(0xFF949BA4),
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: Text(
                      L10n.of(context).dehydrate,
                      style: const TextStyle(color: Color(0xFF949BA4)),
                    ),
                    onTap: dehydrateAction,
                  ),
                  ListTile(
                    iconColor: Colors.red,
                    leading: const Icon(Icons.delete_outlined),
                    title: Text(
                      L10n.of(context).deleteAccount,
                      style: const TextStyle(color: Colors.red),
                    ),
                    onTap: deleteAccountAction,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}


extension on ShareKeysWith {
  String localized(L10n l10n) {
    switch (this) {
      case ShareKeysWith.all:
        return l10n.allDevices;
      case ShareKeysWith.crossVerifiedIfEnabled:
        return l10n.crossVerifiedDevicesIfEnabled;
      case ShareKeysWith.crossVerified:
        return l10n.crossVerifiedDevices;
      case ShareKeysWith.directlyVerifiedOnly:
        return l10n.verifiedDevicesOnly;
    }
  }
}
