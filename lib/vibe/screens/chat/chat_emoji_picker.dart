// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat/sticker_picker_dialog.dart';
import 'package:vibe/vibe/screens/chat/trust_user_key_dialog.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'chat.dart';

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: VibeThemes.animationDuration,
      curve: VibeThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.showEmojiPicker
          ? MediaQuery.sizeOf(context).height / 2
          : 0,
      child: controller.showEmojiPicker
          ? DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: L10n.of(context).emojis),
                      Tab(text: L10n.of(context).stickers),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        EmojiPicker(
                          onEmojiSelected: controller.onEmojiSelected,
                          onBackspacePressed: controller.emojiPickerBackspace,
                          config: Config(
                            locale: Localizations.localeOf(context),
                            emojiViewConfig: EmojiViewConfig(
                              noRecents: const NoRecent(),
                              backgroundColor: VibeSettingsStyle.page(context),
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            // Vibe colours: grey icons, blurple selection.
                            categoryViewConfig: CategoryViewConfig(
                              backspaceColor: VibeSettingsStyle.text2(context),
                              iconColor: VibeSettingsStyle.text2(
                                context,
                              ).withAlpha(150),
                              iconColorSelected: VibePalette.accent,
                              indicatorColor: VibePalette.accent,
                              backgroundColor: VibeSettingsStyle.page(context),
                              dividerColor: VibeSettingsStyle.line(context),
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: VibeSettingsStyle.card(
                                context,
                              ),
                              indicatorColor: VibeSettingsStyle.text2(context),
                            ),
                          ),
                        ),
                        StickerPickerDialog(
                          room: controller.room,
                          onSelected: (sticker) async {
                            final proceed = await showTrustUserInRoomDialog(
                              context,
                              controller.room,
                            );
                            if (!proceed) return;
                            controller.room.sendEvent(
                              {
                                'body': sticker.body,
                                'info': sticker.info ?? {},
                                'url': sticker.url.toString(),
                              },
                              type: EventTypes.Sticker,
                              threadRootEventId: controller.activeThreadId,
                              threadLastEventId: controller.threadLastEventId,
                            );
                            controller.hideEmojiPicker();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
