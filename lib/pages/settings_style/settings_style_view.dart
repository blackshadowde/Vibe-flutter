// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later


import 'package:vibe/vibe/vibe_glass.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/widgets/theme_builder.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/account_config.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/settings_switch_list_tile.dart';
import 'package:vibe/vibe/vibe_text_size.dart';
import 'package:vibe/vibe/vibe_text_size_preview.dart';
import 'package:flutter/material.dart';

import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(L10n.of(context).changeTheme),
      ),
      body: MaxWidthBody(
        child: VibeGroups(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SegmentedButton<ThemeMode>(
                selected: {controller.currentTheme},
                onSelectionChanged: (selected) =>
                    controller.switchTheme(selected.single),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(L10n.of(context).lightTheme),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(L10n.of(context).darkTheme),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(L10n.of(context).systemTheme),
                    icon: const Icon(Icons.auto_mode_outlined),
                  ),
                ],
              ),
            ),
            // Vibe: colours only (backgrounds, accent, buttons); the chat
            // layout stays the same
            ListTile(
              title: Text(
                'Colours',
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                VibePalette.wallpaperAvailable
                    ? 'Material takes your phone\'s colours, like Google Messages. '
                          'Glass is frosted panels over a wallpaper'
                    : 'Material needs Android 12 or newer. '
                          'Glass is frosted panels over a wallpaper',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SegmentedButton<VibeLook>(
                selected: {ThemeController.of(context).look},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    ThemeController.of(context).setLook(s.single),
                segments: [
                  const ButtonSegment(
                    value: VibeLook.vibe,
                    label: Text('Vibe'),
                    icon: Icon(Icons.forum_outlined),
                  ),
                  ButtonSegment(
                    value: VibeLook.wallpaper,
                    label: const Text('Material'),
                    icon: const Icon(Icons.palette_outlined),
                    enabled: VibePalette.wallpaperAvailable,
                  ),
                  const ButtonSegment(
                    value: VibeLook.glass,
                    label: Text('Glass'),
                    icon: Icon(Icons.blur_on_outlined),
                  ),
                ],
              ),
            ),
            if (ThemeController.of(context).look == VibeLook.glass)
              const VibeGlassSettings(),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).messagesStyle,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            StreamBuilder(
              stream: client.onSync.stream.where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) =>
                          accountData.type ==
                          ApplicationAccountConfigExtension.accountDataKey,
                    ) ??
                    false,
              ),
              builder: (context, snapshot) {
                final accountConfig = client.applicationAccountConfig;

                return Column(
                  mainAxisSize: .min,
                  children: [
                    // Looks exactly like a Vibe chat (from Vibgram).
                    VibeTextSizePreview(size: VibeTextSize.value),
                    // Vibe: no chat wallpapers. Only offer removing an
                    // old one that was set before.
                    if (accountConfig.wallpaperUrl != null)
                      ListTile(
                        leading: Icon(
                          Icons.delete_outlined,
                          color: theme.colorScheme.error,
                        ),
                        title: const Text('Remove old chat wallpaper'),
                        onTap: controller.deleteChatWallpaper,
                      ),
                  ],
                );
              },
            ),
            // Telegram's Text size: 12–30, default 16; only message text
            // changes (names and times keep their size).
            ListTile(
              title: const Text('Text size'),
              trailing: Text(
                '${VibeTextSize.value}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider.adaptive(
                      min: VibeTextSize.min.toDouble(),
                      max: VibeTextSize.max.toDouble(),
                      divisions: VibeTextSize.max - VibeTextSize.min,
                      value: VibeTextSize.value.toDouble(),
                      label: '${VibeTextSize.value}',
                      semanticFormatterCallback: (d) => '${d.round()}',
                      onChanged: (d) => controller.changeTextSize(d.round()),
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 24)),
                ],
              ),
            ),
            SettingsSwitchListTile.adaptive(
              title: 'Haptic feedback',
              subtitle: 'Vibrate gently on taps, menus and reactions',
              setting: AppSettings.vibeHaptics,
            ),

          ],
        ),
      ),
    );
  }
}
