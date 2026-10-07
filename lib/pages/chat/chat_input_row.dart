// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/recording_input_row.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/pages/chat/recording_view_model.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_attach_sheet.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import 'chat.dart';
import 'input_bar.dart';

class ChatInputRow extends StatelessWidget {
  final ChatController controller;

  static const double height = 56.0;

  const ChatInputRow(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMessageOnly =
        controller.sendController.text.isNotEmpty ||
        controller.replyEvent != null ||
        controller.editEvent != null;

    if (!controller.room.otherPartyCanReceiveMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selectedTextButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onTertiaryContainer,
    );

    return RecordingViewModel(
      builder: (context, recordingViewModel) {
        if (recordingViewModel.isRecording) {
          return RecordingInputRow(
            state: recordingViewModel,
            onSend: controller.onVoiceMessageSend,
          );
        }
        return Row(
          crossAxisAlignment: .end,
          mainAxisAlignment: .spaceBetween,
          children: controller.selectMode
              ? <Widget>[
                  if (controller.selectedEvents.every(
                    (event) => event.status == EventStatus.error,
                  ))
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: controller.deleteErrorEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.delete_forever_outlined),
                            Text(L10n.of(context).delete),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: selectedTextButtonStyle,
                        onPressed: controller.forwardEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.keyboard_arrow_left_outlined),
                            Text(L10n.of(context).forward),
                          ],
                        ),
                      ),
                    ),
                  controller.selectedEvents.length == 1
                      ? controller.selectedEvents.first
                                .getDisplayEvent(controller.timeline!)
                                .status
                                .isSent
                            ? SizedBox(
                                height: height,
                                child: TextButton(
                                  style: selectedTextButtonStyle,
                                  onPressed: controller.replyAction,
                                  child: Row(
                                    children: <Widget>[
                                      Text(L10n.of(context).reply),
                                      const Icon(Icons.keyboard_arrow_right),
                                    ],
                                  ),
                                ),
                              )
                            : SizedBox(
                                height: height,
                                child: TextButton(
                                  style: selectedTextButtonStyle,
                                  onPressed: controller.sendAgainAction,
                                  child: Row(
                                    children: <Widget>[
                                      Text(L10n.of(context).tryToSendAgain),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.send_outlined, size: 16),
                                    ],
                                  ),
                                ),
                              )
                      : const SizedBox.shrink(),
                ]
              : <Widget>[
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(10, 6, 0, 8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      ReplyDisplay(controller),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Material(
                            color: theme.colorScheme.surfaceContainerHighest,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.add, size: 26),
                                onPressed: () =>
                                    VibeAttachSheet.show(context, controller),
                              ),
                            ),
                          ),
                          if (Matrix.of(context).isMultiAccount &&
                              Matrix.of(context).hasComplexBundles &&
                              Matrix.of(context).currentBundle!.length > 1)
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: _ChatAccountPicker(controller),
                            ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: InputBar(
                                room: controller.room,
                                minLines: 1,
                                maxLines: 8,
                                autofocus: !PlatformInfos.isMobile,
                                keyboardType: TextInputType.multiline,
                                textInputAction:
                                    AppSettings.sendOnEnter.value == true &&
                                        PlatformInfos.isMobile
                                    ? TextInputAction.send
                                    : null,
                                onSubmitted: controller.onInputBarSubmitted,
                                onSubmitImage: controller.sendImageFromClipBoard,
                                focusNode: controller.inputFocus,
                                controller: controller.sendController,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  counter: const SizedBox.shrink(),
                                  hintText:
                                      'Message | ${controller.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)))}',
                                  hintMaxLines: 1,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                ),
                                onChanged: controller.onInputBarChanged,
                                suggestionEmojis:
                                    getDefaultEmojiLocale(
                                      AppSettings
                                              .emojiSuggestionLocale
                                              .value
                                              .isNotEmpty
                                          ? Locale(
                                              AppSettings
                                                  .emojiSuggestionLocale
                                                  .value,
                                            )
                                          : Localizations.localeOf(context),
                                    ).fold(
                                      [],
                                      (emojis, category) =>
                                          emojis..addAll(category.emoji),
                                    ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: L10n.of(context).emojis,
                            icon: Icon(
                              controller.showEmojiPicker
                                  ? Icons.keyboard
                                  : Icons.sentiment_satisfied_alt_outlined,
                              key: ValueKey(controller.showEmojiPicker),
                            ),
                            onPressed: controller.emojiPickerAction,
                          ),
                          if (PlatformInfos.isMobile)
                            IconButton(
                              tooltip: L10n.of(context).takeAPhoto,
                              icon: const Icon(Icons.photo_camera_outlined),
                              onPressed: () =>
                                  controller.onAddPopupMenuButtonSelected(
                                    AddPopupMenuActions.photoCamera,
                                  ),
                            ),
                        ],
                      ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 54,
                    width: 54,
                    alignment: Alignment.center,
                    child:
                        PlatformInfos.platformCanRecord &&
                            !controller.sendController.text.isNotEmpty &&
                            controller.editEvent == null
                        ? HoverBuilder(
                            builder: (context, hovered) => IconButton(
                              tooltip: L10n.of(context).voiceMessage,
                              onPressed: hovered
                                  ? () => recordingViewModel.startRecording(
                                      controller.room,
                                    )
                                  : () => ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                          SnackBar(
                                            margin: EdgeInsets.only(
                                              bottom: height + 16,
                                              left: 16,
                                              right: 16,
                                              top: 16,
                                            ),
                                            showCloseIcon: true,
                                            content: Text(
                                              L10n.of(
                                                context,
                                              ).longPressToRecordVoiceMessage,
                                            ),
                                          ),
                                        ),
                              onLongPress: () => recordingViewModel
                                  .startRecording(controller.room),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFDCE4FF),
                                foregroundColor: const Color(0xFF226DFD),
                                fixedSize: const Size(54, 54),
                              ),
                              icon: const Icon(Icons.graphic_eq, size: 28),
                            ),
                          )
                        : IconButton(
                            key: Key('send_button'),
                            tooltip: L10n.of(context).send,
                            onPressed: controller.send,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFDCE4FF),
                              foregroundColor: const Color(0xFF226DFD),
                              fixedSize: const Size(54, 54),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 24),
                          ),
                  ),
                  const SizedBox(width: 10),
                ],
        );
      },
    );
  }
}

class _ChatAccountPicker extends StatelessWidget {
  final ChatController controller;

  const _ChatAccountPicker(this.controller);

  void _popupMenuButtonSelected(String mxid, BuildContext context) {
    final client = Matrix.of(
      context,
    ).currentBundle!.firstWhere((cl) => cl!.userID == mxid, orElse: () => null);
    if (client == null) {
      Logs().w('Attempted to switch to a non-existing client $mxid');
      return;
    }
    controller.setSendingClient(client);
  }

  @override
  Widget build(BuildContext context) {
    final clients = controller.currentRoomBundle;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FutureBuilder<Profile>(
        future: controller.sendingClient.fetchOwnProfile(),
        builder: (context, snapshot) => PopupMenuButton<String>(
          useRootNavigator: true,
          onSelected: (mxid) => _popupMenuButtonSelected(mxid, context),
          itemBuilder: (BuildContext context) => clients
              .map(
                (client) => PopupMenuItem(
                  value: client!.userID,
                  child: FutureBuilder<Profile>(
                    future: client.fetchOwnProfile(),
                    builder: (context, snapshot) => ListTile(
                      leading: Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name:
                            snapshot.data?.displayName ??
                            client.userID!.localpart,
                        size: 20,
                      ),
                      title: Text(snapshot.data?.displayName ?? client.userID!),
                      contentPadding: const EdgeInsets.all(0),
                    ),
                  ),
                ),
              )
              .toList(),
          child: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name:
                snapshot.data?.displayName ??
                Matrix.of(context).client.userID!.localpart,
            size: 20,
          ),
        ),
      ),
    );
  }
}
