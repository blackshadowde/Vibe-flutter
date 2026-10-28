// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/adaptive_bottom_sheet.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/vibe/vibe_media_saver.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/settings_switch_list_tile.dart';
import 'package:vibe/vibe/vibe_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'settings_chat.dart';

class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).chat),
        automaticallyImplyLeading: !VibeThemes.isColumnMode(context),
        centerTitle: VibeThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: VibeGroups(
            children: [
              SettingsSwitchListTile.adaptive(
                title: 'Low data mode',
                subtitle:
                    'Photos load only when you tap them, GIFs don\'t '
                    'autoplay, photos you send are smaller and nothing is '
                    'saved to the gallery automatically.',
                setting: AppSettings.vibeLowData,
                onChanged: (_) => controller.updateState(),
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).formattedMessages,
                subtitle: L10n.of(context).formattedMessagesDescription,
                setting: AppSettings.renderHtml,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideRedactedMessages,
                subtitle: L10n.of(context).hideRedactedMessagesBody,
                setting: AppSettings.hideRedactedEvents,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideRoomsInSpaces,
                setting: AppSettings.hideRoomsInSpaces,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).hideInvalidOrUnknownMessageFormats,
                setting: AppSettings.hideUnknownEvents,
              ),
              if (PlatformInfos.isMobile)
                SettingsSwitchListTile.adaptive(
                  title: L10n.of(context).autoplayImages,
                  setting: AppSettings.autoplayImages,
                ),
              if (PlatformInfos.isMobile)
                SettingsSwitchListTile.adaptive(
                  title: 'Save media to gallery',
                  subtitle:
                      'Photos and videos you receive are saved to your '
                      'phone automatically, so they stay even if the '
                      'server deletes old media.',
                  setting: AppSettings.vibeSaveMedia,
                  onChanged: (on) async {
                    if (!on) return;
                    final ok = await VibeMediaSaver.requestPermission();
                    if (!ok) {
                      await AppSettings.vibeSaveMedia.setItem(false);
                      controller.updateState();
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Storage & cache'),
                subtitle: Text(
                  'Cache ${VibeStorage.label(VibeStorage.cacheLimits, AppSettings.vibeCacheLimitMb.value)} · '
                  'keep media ${VibeStorage.label(VibeStorage.keepOptions, AppSettings.vibeKeepMediaDays.value).toLowerCase()}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await VibeStoragePage.open(context);
                  controller.updateState();
                },
              ),
              SettingsSwitchListTile.adaptive(
                title: 'Status bubble in chats',
                subtitle:
                    'Show the other person\'s status and local time in a '
                    'bubble at the top of the chat.',
                setting: AppSettings.vibeStatusBubble,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).sendOnEnter,
                setting: AppSettings.sendOnEnter,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).swipeRightToLeftToReply,
                setting: AppSettings.swipeRightToLeftToReply,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).showThumbnailsInTimeline,
                setting: AppSettings.showThumbnailsInTimeline,
              ),
              SettingsSwitchListTile.adaptive(
                title: L10n.of(context).doubleTapToReact,
                subtitle: L10n.of(context).doubleTapToReactDescription,
                setting: AppSettings.doubleTapToReact,
                onChanged: (_) => controller.updateState(),
              ),
              if (AppSettings.doubleTapToReact.value)
                ListTile(
                  title: Text(L10n.of(context).doubleTapReaction),
                  trailing: Text(
                    AppSettings.doubleTapReaction.value,
                    style: const TextStyle(fontSize: 24),
                  ),
                  onTap: () async {
                    final emoji = await showAdaptiveBottomSheet<String>(
                      context: context,
                      builder: (context) => Scaffold(
                        appBar: AppBar(
                          title: Text(L10n.of(context).doubleTapReaction),
                          leading: CloseButton(
                            onPressed: () => Navigator.of(context).pop(null),
                          ),
                        ),
                        body: SizedBox(
                          height: double.infinity,
                          child: EmojiPicker(
                            onEmojiSelected: (_, emoji) =>
                                Navigator.of(context).pop(emoji.emoji),
                            config: Config(
                              locale: Localizations.localeOf(context),
                              emojiViewConfig: const EmojiViewConfig(
                                backgroundColor: Colors.transparent,
                              ),
                              bottomActionBarConfig:
                                  const BottomActionBarConfig(enabled: false),
                              categoryViewConfig: CategoryViewConfig(
                                initCategory: Category.SMILEYS,
                                backspaceColor: theme.colorScheme.primary,
                                iconColor: theme.colorScheme.primary.withAlpha(
                                  128,
                                ),
                                iconColorSelected: theme.colorScheme.primary,
                                indicatorColor: theme.colorScheme.primary,
                                backgroundColor: theme.colorScheme.surface,
                              ),
                              skinToneConfig: SkinToneConfig(
                                dialogBackgroundColor: Color.lerp(
                                  theme.colorScheme.surface,
                                  theme.colorScheme.primaryContainer,
                                  0.75,
                                )!,
                                indicatorColor: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    if (emoji != null) {
                      await AppSettings.doubleTapReaction.setItem(emoji);
                      controller.updateState();
                    }
                  },
                ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).customEmojisAndStickers,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                title: Text(L10n.of(context).customEmojisAndStickers),
                subtitle: Text(L10n.of(context).customEmojisAndStickersBody),
                onTap: () => context.go('/rooms/settings/chat/emotes'),
                trailing: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Icon(Icons.chevron_right_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
