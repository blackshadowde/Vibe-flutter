// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:flutter/material.dart';

class SettingsSwitchListTile extends StatefulWidget {
  final AppSettings<bool> setting;
  final String title;
  final String? subtitle;
  final Function(bool)? onChanged;

  const SettingsSwitchListTile.adaptive({
    super.key,
    required this.setting,
    required this.title,
    this.subtitle,
    this.onChanged,
  });

  @override
  SettingsSwitchListTileState createState() => SettingsSwitchListTileState();
}

class SettingsSwitchListTileState extends State<SettingsSwitchListTile> {
  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
    // Vibe: slim Discord-style switch, whole row tappable.
    return VibeSwitchRow(
      value: widget.setting.value,
      title: widget.title,
      subtitle: subtitle,
      onChanged: (bool newValue) async {
        widget.onChanged?.call(newValue);
        await widget.setting.setItem(newValue);
        setState(() {});
      },
    );
  }
}
