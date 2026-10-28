// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/permission_slider_dialog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/screens/chat_permissions_settings/permission_list_tile.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';

class ChatPermissionsSettings extends StatefulWidget {
  const ChatPermissionsSettings({super.key});

  @override
  _ChatPermissionsSettingsState createState() =>
      _ChatPermissionsSettingsState();
}

class _ChatPermissionsSettingsState extends State<ChatPermissionsSettings> {
  String? get roomId => GoRouterState.of(context).pathParameters['roomid'];
  Future<void> editPowerLevel(
    BuildContext context,
    String key,
    int currentLevel, {
    int? newLevel,
    String? category,
  }) async {
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    if (!room.canSendEvent(EventTypes.RoomPowerLevels)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.of(context).noPermission)));
      return;
    }
    newLevel ??= await showPermissionChooser(
      context,
      currentLevel: currentLevel,
    );
    if (newLevel == null) return;
    if (!context.mounted) return;
    final content = Map<String, dynamic>.from(
      room.getState(EventTypes.RoomPowerLevels)!.content,
    );
    if (category != null) {
      if (!content.containsKey(category)) {
        content[category] = <String, dynamic>{};
      }
      content[category][key] = newLevel;
    } else {
      content[key] = newLevel;
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.client.setRoomStateWithKey(
        room.id,
        EventTypes.RoomPowerLevels,
        '',
        content,
      ),
    );
  }

  Stream get onChanged => Matrix.of(context).client.onSync.stream.where(
    (e) =>
        (e.rooms?.join?.containsKey(roomId) ?? false) &&
        (e.rooms!.join![roomId!]?.timeline?.events?.any(
              (s) => s.type == EventTypes.RoomPowerLevels,
            ) ??
            false),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).chatPermissions),
      ),
      body: MaxWidthBody(
        child: StreamBuilder(
          stream: onChanged,
          builder: (context, _) {
            final roomId = this.roomId;
            final room = roomId == null
                ? null
                : Matrix.of(context).client.getRoomById(roomId);
            if (room == null) {
              return Center(child: Text(L10n.of(context).noRoomsFound));
            }
            final powerLevelsContent = Map<String, Object?>.from(
              room.getState(EventTypes.RoomPowerLevels)?.content ?? {},
            );
            final powerLevels = Map<String, dynamic>.from(powerLevelsContent)
              ..removeWhere((k, v) => v is! int);
            final eventsPowerLevels = Map<String, int?>.from(
              powerLevelsContent.tryGetMap<String, int?>('events') ?? {},
            )..removeWhere((k, v) => v is! int);
            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outlined),
                  subtitle: const Text(
                    'Choose who can do each thing in this chat: everyone, '
                    'moderators and admins, or admins only.',
                  ),
                ),
                Divider(color: theme.dividerColor),
                ListTile(
                  title: Text(
                    L10n.of(context).chatPermissions,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: .min,
                  children: [
                    for (final entry in powerLevels.entries)
                      PermissionsListTile(
                        permissionKey: entry.key,
                        permission: entry.value,
                        onChanged: (level) => editPowerLevel(
                          context,
                          entry.key,
                          entry.value,
                          newLevel: level,
                        ),
                        canEdit: room.canChangePowerLevel,
                      ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: Text(
                        L10n.of(context).notifications,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        const key = 'rooms';
                        final value =
                            powerLevelsContent.containsKey('notifications')
                            ? powerLevelsContent
                                      .tryGetMap<String, Object?>(
                                        'notifications',
                                      )
                                      ?.tryGet<int>('rooms') ??
                                  0
                            : 0;
                        return PermissionsListTile(
                          permissionKey: key,
                          permission: value,
                          category: 'notifications',
                          canEdit: room.canChangePowerLevel,
                          onChanged: (level) => editPowerLevel(
                            context,
                            key,
                            value,
                            newLevel: level,
                            category: 'notifications',
                          ),
                        );
                      },
                    ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: Text(
                        L10n.of(context).configureChat,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    for (final entry in eventsPowerLevels.entries)
                      PermissionsListTile(
                        permissionKey: entry.key,
                        category: 'events',
                        permission: entry.value ?? 0,
                        canEdit: room.canChangePowerLevel,
                        onChanged: (level) => editPowerLevel(
                          context,
                          entry.key,
                          entry.value ?? 0,
                          newLevel: level,
                          category: 'events',
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

