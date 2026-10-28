// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/app_config.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class PermissionsListTile extends StatelessWidget {
  final String permissionKey;
  final int permission;
  final String? category;
  final void Function(int? level)? onChanged;
  final bool canEdit;

  const PermissionsListTile({
    super.key,
    required this.permissionKey,
    required this.permission,
    this.category,
    required this.onChanged,
    required this.canEdit,
  });

  /// Null for keys Vibe doesn't explain (they stay as they are, hidden).
  String? getLocalizedPowerLevelString(BuildContext context) {
    if (category == null) {
      switch (permissionKey) {
        case 'users_default':
          return L10n.of(context).defaultPermissionLevel;
        case 'events_default':
          return L10n.of(context).sendMessages;
        case 'state_default':
          return L10n.of(context).changeGeneralChatSettings;
        case 'ban':
          return L10n.of(context).banFromChat;
        case 'kick':
          return L10n.of(context).kickFromChat;
        case 'redact':
          return L10n.of(context).deleteMessage;
        case 'invite':
          return L10n.of(context).inviteOtherUsers;
      }
    } else if (category == 'notifications') {
      switch (permissionKey) {
        case 'rooms':
          return L10n.of(context).sendRoomNotifications;
      }
    } else if (category == 'events') {
      switch (permissionKey) {
        case EventTypes.RoomName:
          return L10n.of(context).changeTheNameOfTheGroup;
        case EventTypes.RoomTopic:
          return L10n.of(context).changeTheDescriptionOfTheGroup;
        case EventTypes.RoomPowerLevels:
          return L10n.of(context).changeTheChatPermissions;
        case EventTypes.HistoryVisibility:
          return L10n.of(context).changeTheVisibilityOfChatHistory;
        case EventTypes.RoomCanonicalAlias:
          return L10n.of(context).changeTheCanonicalRoomAlias;
        case EventTypes.RoomAvatar:
          return L10n.of(context).editRoomAvatar;
        case EventTypes.RoomTombstone:
          return L10n.of(context).replaceRoomWithNewerVersion;
        case EventTypes.Encryption:
          return L10n.of(context).enableEncryption;
        case 'm.room.server_acl':
          return L10n.of(context).editBlockedServers;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = getLocalizedPowerLevelString(context);
    if (title == null) return const SizedBox.shrink();

    // Three simple levels: everyone, moderators, admins.
    final level = permission >= 100
        ? 100
        : permission >= 50
        ? 50
        : 0;
    final color = level == 100
        ? Colors.orangeAccent
        : level == 50
        ? Colors.blueAccent
        : Colors.greenAccent;
    return ListTile(
      title: Text(title, style: theme.textTheme.titleSmall),
      trailing: Material(
        color: color.withAlpha(32),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        child: DropdownButton<int>(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          underline: const SizedBox.shrink(),
          onChanged: canEdit
              ? (v) {
                  if (v != null && v != level) onChanged?.call(v);
                }
              : null,
          value: level,
          items: [
            DropdownMenuItem(
              value: 0,
              child: Text(
                permissionKey == 'users_default' ? 'Member' : 'Everyone',
              ),
            ),
            DropdownMenuItem(
              value: 50,
              child: Text(
                permissionKey == 'users_default' ? 'Moderator' : 'Moderators',
              ),
            ),
            DropdownMenuItem(
              value: 100,
              child: Text(
                permissionKey == 'users_default' ? 'Admin' : 'Admins',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
