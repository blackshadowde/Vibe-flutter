// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/settings/settings.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:vibe/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/vibe/vibe_dialog.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/vibe/screens/chat_details/participant_list_item.dart';
import 'package:vibe/utils/verified_room_extension.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/chat_settings_popup_menu.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/widgets/mxc_image_viewer.dart';
import 'package:vibe/widgets/qr_code_viewer.dart';

class ChatDetails extends StatefulWidget {
  final String roomId;
  final Widget? embeddedCloseButton;

  const ChatDetails({
    super.key,
    required this.roomId,
    this.embeddedCloseButton,
  });

  @override
  _ChatDetailsState createState() => _ChatDetailsState();
}

class _ChatDetailsState extends State<ChatDetails> {
  bool displaySettings = false;

  void toggleDisplaySettings() =>
      setState(() => displaySettings = !displaySettings);

  String? get roomId => widget.roomId;

  Future<void> setDisplaynameAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: l10n.changeTheNameOfTheGroup,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: room.getLocalizedDisplayname(MatrixLocals(l10n)),
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setName(input),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.displaynameHasBeenChanged)),
      );
    }
  }

  Future<void> setTopicAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: l10n.setChatDescription,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.noChatDescriptionYet,
      initialText: room.topic,
      minLines: 4,
      maxLines: 8,
    );
    if (input == null) return;
    if (!mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setDescription(input),
    );
    if (!mounted) return;
    if (success.error == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.chatDescriptionHasBeenChanged)),
      );
    }
  }

  Future<void> setAvatarAction() async {
    final l10n = L10n.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!);
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: l10n.openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: l10n.openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (room?.avatar != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: l10n.delete,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: l10n.editRoomAvatar,
            cancelLabel: l10n.cancel,
            actions: actions,
          );
    if (action == null) return;
    if (!mounted) return;
    if (action == AvatarAction.remove) {
      await showFutureLoadingDialog(
        context: context,
        future: () => room!.setAvatar(null),
      );
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      if (!mounted) return;
      final picked = await selectFiles(
        context,
        allowMultiple: false,
        type: FileType.image,
      );
      final pickedFile = picked.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room!.setAvatar(file),
    );
  }

  static const fixedWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final room = Matrix.of(context).client.getRoomById(roomId!);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }

    final directChatMatrixID = room.directChatMatrixID;
    final roomAvatar = room.avatar;

    return StreamBuilder(
      stream: room.client.onRoomState.stream.where(
        (update) => update.roomId == room.id,
      ),
      builder: (context, snapshot) {
        var members = room.getParticipants().toList()
          ..sort((b, a) => a.powerLevel.level.compareTo(b.powerLevel.level));
        members = members.take(10).toList();
        final actualMembersCount =
            (room.summary.mInvitedMemberCount ?? 0) +
            (room.summary.mJoinedMemberCount ?? 0);
        final canRequestMoreMembers = members.length < actualMembersCount;
        final iconColor = theme.textTheme.bodyLarge!.color;
        final displayname = room.getLocalizedDisplayname(
          MatrixLocals(L10n.of(context)),
        );
        return Scaffold(
          appBar: AppBar(
            leading:
                widget.embeddedCloseButton ??
                const Center(child: BackButton()),
            elevation: theme.appBarTheme.elevation,
            actions: <Widget>[
              if (room.canonicalAlias.isNotEmpty)
                IconButton(
                  tooltip: L10n.of(context).share,
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: () =>
                      showQrCodeViewer(context, room.canonicalAlias),
                )
              else if (directChatMatrixID != null)
                IconButton(
                  tooltip: L10n.of(context).share,
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: () =>
                      showQrCodeViewer(context, directChatMatrixID),
                ),
              if (widget.embeddedCloseButton == null)
                ChatSettingsPopupMenu(room, false),
            ],
            title: Text(L10n.of(context).chatDetails),
            backgroundColor: theme.appBarTheme.backgroundColor,
          ),
          body: MaxWidthBody(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: members.length + 1 + (canRequestMoreMembers ? 1 : 0),
              itemBuilder: (BuildContext context, int i) => i == 0
                  ? Column(
                      crossAxisAlignment: .stretch,
                      children: <Widget>[
                        Center(
                          child: Stack(
                            children: [
                              Hero(
                                tag:
                                    widget.embeddedCloseButton !=
                                        null
                                    ? 'embedded_content_banner'
                                    : 'content_banner',
                                child: Avatar(
                                  mxContent: room.avatar,
                                  name: displayname,
                                  size: Avatar.defaultSize * 2.5,
                                  onTap: roomAvatar != null
                                      ? () => showVibeDialog(
                                          context: context,
                                          builder: (_) =>
                                              MxcImageViewer(roomAvatar),
                                        )
                                      : null,
                                ),
                              ),
                              if (!room.isDirectChat &&
                                  room.canChangeStateEvent(
                                    EventTypes.RoomAvatar,
                                  ))
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: FloatingActionButton.small(
                                    onPressed: setAvatarAction,
                                    heroTag: null,
                                    child: const Icon(
                                      Icons.camera_alt_outlined,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Center(
                            child: TextButton.icon(
                              onPressed:
                                  room.isDirectChat ||
                                      !room.canChangeStateEvent(
                                        EventTypes.RoomName,
                                      )
                                  ? null
                                  : setDisplaynameAction,
                              icon:
                                  room.isDirectChat ||
                                      !room.canChangeStateEvent(
                                        EventTypes.RoomName,
                                      )
                                  ? null
                                  : Icon(Icons.edit_outlined, size: 16),

                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.onSurface,
                                iconColor: theme.colorScheme.onSurface,
                                disabledForegroundColor:
                                    theme.colorScheme.onSurface,
                              ),
                              label: Row(
                                mainAxisSize: .min,
                                spacing: 4,
                                children: [
                                  if (room.allUsersVerified)
                                    Icon(
                                      Icons.verified,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 18,
                                    ),
                                  Text(
                                    displayname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        StreamBuilder(
                          stream: room.client.onSync.stream.where(
                            (s) =>
                                s.accountData?.any(
                                  (data) => data.type == 'm.push_rules',
                                ) ??
                                false,
                          ),
                          builder: (context, _) => Wrap(
                            alignment: .center,
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _MainChatDetailsButton(
                                onPressed: () =>
                                    context.go('/rooms/${room.id}/search'),
                                label: L10n.of(context).search,
                                icon: Icons.search,
                              ),
                              _MainChatDetailsButton(
                                onPressed: () => context.push(
                                  '/rooms/${room.id}/details/emotes',
                                ),
                                label: L10n.of(context).stickers,
                                icon: Icons.emoji_emotions_outlined,
                              ),
                              if (room.pushRuleState == PushRuleState.notify)
                                _MainChatDetailsButton(
                                  onPressed: () => showFutureLoadingDialog(
                                    context: context,
                                    future: () => room.setPushRuleState(
                                      PushRuleState.mentionsOnly,
                                    ),
                                  ),
                                  label: L10n.of(context).mute,
                                  icon: Icons.notifications_on_outlined,
                                )
                              else
                                _MainChatDetailsButton(
                                  onPressed: () => showFutureLoadingDialog(
                                    context: context,
                                    future: () => room.setPushRuleState(
                                      PushRuleState.notify,
                                    ),
                                  ),
                                  label: L10n.of(context).unmuteChat,
                                  icon: Icons.notifications_off_outlined,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (room.canChangeStateEvent(EventTypes.RoomTopic) ||
                            room.topic.isNotEmpty) ...[
                          ListTile(
                            title: Text(
                              L10n.of(context).chatDescription,
                              style: TextStyle(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing:
                                room.canChangeStateEvent(EventTypes.RoomTopic)
                                ? IconButton(
                                    onPressed: setTopicAction,
                                    tooltip: L10n.of(
                                      context,
                                    ).setChatDescription,
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: SelectableLinkify(
                              text: room.topic.isEmpty
                                  ? L10n.of(context).noChatDescriptionYet
                                  : room.topic,
                              textScaleFactor: MediaQuery.textScalerOf(
                                context,
                              ).scale(1),
                              options: const LinkifyOptions(humanize: false),
                              linkStyle: const TextStyle(
                                color: Colors.blueAccent,
                                decorationColor: Colors.blueAccent,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: room.topic.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: theme.textTheme.bodyMedium!.color,
                                decorationColor:
                                    theme.textTheme.bodyMedium!.color,
                              ),
                              onOpen: (url) =>
                                  UrlLauncher(context, url.url).launchUrl(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!room.isDirectChat) ...[
                          Divider(color: theme.dividerColor),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.surfaceContainer,
                              foregroundColor: iconColor,
                              child: const Icon(
                                Icons.admin_panel_settings_outlined,
                              ),
                            ),
                            title: Text(L10n.of(context).accessAndVisibility),
                            subtitle: Text(
                              L10n.of(context).accessAndVisibilityDescription,
                            ),
                            onTap: () => context.push(
                              '/rooms/${room.id}/details/access',
                            ),
                            trailing: const Icon(Icons.chevron_right_outlined),
                          ),
                          ListTile(
                            title: Text(L10n.of(context).chatPermissions),
                            subtitle: Text(
                              L10n.of(context).whoCanPerformWhichAction,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.surfaceContainer,
                              foregroundColor: iconColor,
                              child: const Icon(Icons.tune_outlined),
                            ),
                            trailing: const Icon(Icons.chevron_right_outlined),
                            onTap: () => context.push(
                              '/rooms/${room.id}/details/permissions',
                            ),
                          ),
                        ],
                        Divider(color: theme.dividerColor),
                        ListTile(
                          title: Text(
                            L10n.of(
                              context,
                            ).countParticipants(actualMembersCount),
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: !room.isDirectChat && room.canInvite
                              ? TextButton.icon(
                                  icon: Icon(Icons.add),
                                  label: Text(L10n.of(context).invite),
                                  onPressed: () =>
                                      context.go('/rooms/${room.id}/invite'),
                                )
                              : null,
                        ),
                      ],
                    )
                  : i < members.length + 1
                  ? ParticipantListItem(members[i - 1])
                  : ListTile(
                      title: Text(
                        L10n.of(context).loadCountMoreParticipants(
                          (actualMembersCount - members.length),
                        ),
                      ),
                      onTap: () => context.push(
                        '/rooms/${roomId!}/details/members',
                      ),
                      trailing: const Icon(Icons.chevron_right_outlined),
                    ),
            ),
          ),
        );
      },
    );
  }
}


class _MainChatDetailsButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  const _MainChatDetailsButton({
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: .center,
            mainAxisSize: .min,
            children: [
              Icon(icon, color: theme.colorScheme.secondary),
              SizedBox(
                width: 64,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: TextStyle(color: theme.colorScheme.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
