// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_dialog.dart';
import 'dart:convert';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/vibe_push_rules.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/utils/background_push.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/push_helper.dart';
import 'package:vibe/vibe/vibe_push_mode_tiles.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/settings_switch_list_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_ui/unifiedpush_ui.dart';

class VibeNotificationsPage extends StatefulWidget {
  const VibeNotificationsPage({super.key});

  @override
  VibeNotificationsPageController createState() =>
      VibeNotificationsPageController();
}

class _VibeNotificationsPageState extends State<VibeNotificationsPage> {
  bool isLoading = false;

  Future<void> onPusherTap(Pusher pusher) async {
    final delete = await showModalActionPopup<bool>(
      context: context,
      title: pusher.deviceDisplayName,
      message: '${pusher.appDisplayName} (${pusher.appId})',
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).delete,
          isDestructive: true,
          value: true,
        ),
      ],
    );
    if (delete != true) return;
    if (!mounted) return;

    final success = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context).client.deletePusher(
        PusherId(appId: pusher.appId, pushkey: pusher.pushkey),
      ),
    );

    if (success.error != null) return;

    setState(() {
      pusherFuture = null;
    });
  }

  Future<List<Pusher>?>? pusherFuture;

  Future<void> togglePushRule(PushRuleKind kind, PushRule pushRule) async {
    setState(() {
      isLoading = true;
    });
    try {
      final updateFromSync = Matrix.of(context).client.onSync.stream
          .where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          )
          .first;
      await Matrix.of(
        context,
      ).client.setPushRuleEnabled(kind, pushRule.ruleId, !pushRule.enabled);
      await updateFromSync;
    } catch (e, s) {
      Logs().w('Unable to toggle push rule', e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> editPushRule(PushRule rule, PushRuleKind kind) async {
    final theme = Theme.of(context);
    final action = await showVibeDialog<PushRuleDialogAction>(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: AlertDialog.adaptive(
          title: Text(rule.getPushRuleName(L10n.of(context))),
          content: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Material(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: theme.colorScheme.surfaceContainer,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  prettyJson(rule.toJson()),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
            ),
          ),
          actions: [
            AdaptiveDialogAction(
              onPressed: Navigator.of(context).pop,
              child: Text(L10n.of(context).close),
            ),
            if (!rule.ruleId.startsWith('.m.'))
              AdaptiveDialogAction(
                onPressed: () =>
                    Navigator.of(context).pop(PushRuleDialogAction.delete),
                child: Text(
                  L10n.of(context).delete,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (!mounted) return;
    switch (action) {
      case PushRuleDialogAction.delete:
        final consent = await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context).areYouSure,
          message: L10n.of(context).deletePushRuleCanNotBeUndone,
          okLabel: L10n.of(context).delete,
          isDestructive: true,
        );
        if (consent != OkCancelResult.ok) return;
        if (!mounted) return;
        setState(() {
          isLoading = true;
        });
        try {
          final updateFromSync = Matrix.of(context).client.onSync.stream
              .where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) => accountData.type == 'm.push_rules',
                    ) ??
                    false,
              )
              .first;
          await Matrix.of(context).client.deletePushRule(kind, rule.ruleId);
          await updateFromSync;
        } catch (e, s) {
          Logs().w('Unable to delete push rule', e, s);
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
        } finally {
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
        }
        return;
    }
  }

}

enum PushRuleDialogAction { delete }

String prettyJson(Map<String, Object?> json) {
  const decoder = JsonDecoder();
  const encoder = JsonEncoder.withIndent('    ');
  final object = decoder.convert(jsonEncode(json));
  return encoder.convert(object);

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
        automaticallyImplyLeading: !VibeThemes.isColumnMode(context),
        centerTitle: VibeThemes.isColumnMode(context),
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
                              editPushRule(rule, category.kind),
                          subtitle: Text(
                            rule.getPushRuleDescription(L10n.of(context)),
                          ),
                          trailing: Switch.adaptive(
                            value: rule.enabled,
                            onChanged: isLoading
                                ? null
                                : rule.ruleId != '.m.rule.master' &&
                                      Matrix.of(
                                        context,
                                      ).client.allPushNotificationsMuted
                                ? null
                                : (_) => togglePushRule(
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
