// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/pages/settings_notifications/push_rule_extensions.dart';
import 'package:vibe/utils/background_push.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/push_helper.dart';
import 'package:vibe/vibe/vibe_push_mode_tiles.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/settings_switch_list_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_ui/unifiedpush_ui.dart';

import '../../utils/localized_exception_extension.dart';
import '../../widgets/matrix.dart';
import 'settings_notifications.dart';

class SettingsNotificationsView extends StatelessWidget {
  final SettingsNotificationsController controller;

  const SettingsNotificationsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final pushRules = Matrix.of(context).client.globalPushRules;
    final pushCategories = [
      if (pushRules?.override?.isNotEmpty ?? false)
        (rules: pushRules?.override ?? [], kind: PushRuleKind.override),
      if (pushRules?.content?.isNotEmpty ?? false)
        (rules: pushRules?.content ?? [], kind: PushRuleKind.content),
      if (pushRules?.sender?.isNotEmpty ?? false)
        (rules: pushRules?.sender ?? [], kind: PushRuleKind.sender),
      if (pushRules?.underride?.isNotEmpty ?? false)
        (rules: pushRules?.underride ?? [], kind: PushRuleKind.underride),
    ];
    final pushService = Matrix.of(context).backgroundPush;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(L10n.of(context).notifications),
      ),
      body: MaxWidthBody(
        child: StreamBuilder(
          stream: Matrix.of(context).client.onSync.stream.where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          ),
          builder: (BuildContext context, _) {
            final theme = Theme.of(context);
            final lastReceivedPush =
                lastReceivedPushNotification[Matrix.of(
                  context,
                ).client.clientName];
            return SelectionArea(
              child: VibeGroups(
                children: [
                  if (PlatformInfos.isAndroid) const VibePushModeTiles(),
                  if (PlatformInfos.isAndroid) const Divider(),
                  SettingsSwitchListTile.adaptive(
                    title: 'Notification privacy',
                    subtitle:
                        'Hide names, messages and pictures: notifications only say "New message"',
                    setting: AppSettings.vibeHideNotificationContent,
                  ),
                  if (kDebugMode && lastReceivedPush != null)
                    ListTile(
                      title: Text('Last received push notification'),
                      subtitle: Text(lastReceivedPush.toIso8601String()),
                    ),
                  if (kIsWeb)
                    SettingsSwitchListTile.adaptive(
                      title: L10n.of(context).playSoundOnNotification,
                      setting: AppSettings.webNotificationSound,
                    ),
                  if (pushRules != null)
                    for (final category in pushCategories) ...[
                      ListTile(
                        title: Text(
                          category.kind.localized(L10n.of(context)),
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      for (final rule in category.rules)
                        ListTile(
                          title: Text(rule.getPushRuleName(L10n.of(context))),
                          // Tap the row for the rule's details (FluffyChat
                          // had an underlined "More" link here).
                          onTap: () =>
                              controller.editPushRule(rule, category.kind),
                          subtitle: Text(
                            rule.getPushRuleDescription(L10n.of(context)),
                          ),
                          trailing: Switch.adaptive(
                            value: rule.enabled,
                            onChanged: controller.isLoading
                                ? null
                                : rule.ruleId != '.m.rule.master' &&
                                      Matrix.of(
                                        context,
                                      ).client.allPushNotificationsMuted
                                ? null
                                : (_) => controller.togglePushRule(
                                    category.kind,
                                    rule,
                                  ),
                          ),
                        ),
                      Divider(color: theme.dividerColor),
                    ],

                  if (PlatformInfos.isAndroid)
                    FutureBuilder(
                      future: UnifiedPush.getDistributors(),
                      builder: (context, snapshot) {
                        final distributors = snapshot.data;
                        if (distributors == null || distributors.isEmpty) {
                          if (pushService?.firebaseEnabled == true &&
                              pushService?.fcmToken == null) {
                            return ListTile(
                              title: Text(
                                L10n.of(
                                  context,
                                ).unableToRegisterDeviceForFirebase,
                              ),
                              leading: Icon(
                                Icons.close,
                                color: theme.colorScheme.error,
                              ),
                            );
                          }
                          return SizedBox.shrink();
                        }
                        return ListTile(
                          title: Text(L10n.of(context).unifiedPushDistributors),
                          leading: Icon(Icons.info_outlined),
                          subtitle: SelectableText(distributors.join(', ')),
                          trailing: distributors.length >= 2
                              ? IconButton(
                                  onPressed: () => UnifiedPushUi(
                                    context: context,
                                    instances: ['default'],
                                    unifiedPushFunctions: UPFunctions(),
                                    showNoDistribDialog: false,
                                    onNoDistribDialogDismissed:
                                        () {}, // TODO: Implement me
                                  ).registerAppWithDialog(),
                                  icon: Icon(Icons.edit_outlined),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                    foregroundColor:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  // (the technical list of push registrations, with the old
                  // Google / Firebase one, is no longer shown)
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
