// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Battery saver: fewer animations (no hot-word scenes, heart bursts or the
/// samurai, network lines still, Flutter's "reduce motion") and the screen
/// capped at 60 Hz. On by hand, automatically at a battery level (not while
/// charging), or whenever the phone's own battery saver is on.
abstract class VibeBattery {
  static const _channel = MethodChannel('vibe/system');

  /// Is battery saver on right now?
  static final saving = ValueNotifier<bool>(false);

  /// Last reading (for the settings page).
  static int? level;
  static bool charging = false;
  static bool phoneSaver = false;

  static Future<void> refresh() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('battery');
      if (r != null) {
        final l = r['level'];
        level = l is int && l >= 0 ? l : null;
        charging = r['charging'] == true;
        phoneSaver = r['powerSave'] == true;
      }
    } catch (_) {}
    final at = AppSettings.vibeBatteryAutoAt.value;
    final on =
        AppSettings.vibeBatterySaver.value ||
        (AppSettings.vibeBatteryFollowPhone.value && phoneSaver) ||
        (at > 0 && !charging && level != null && level! <= at);
    if (on != saving.value) {
      saving.value = on;
      try {
        await _channel.invokeMethod('maxRefresh', {'hz': on ? 60 : 0});
      } catch (_) {}
    }
  }
}

/// Keeps battery saver up to date (every minute and when the app comes
/// back) and turns on "reduce motion" for the app while it's on.
class VibeBatteryHost extends StatefulWidget {
  final Widget child;
  const VibeBatteryHost({required this.child, super.key});

  @override
  State<VibeBatteryHost> createState() => _VibeBatteryHostState();
}

class _VibeBatteryHostState extends State<VibeBatteryHost> {
  Timer? _timer;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    VibeBattery.saving.addListener(_changed);
    VibeBattery.refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => VibeBattery.refresh());
    _life = AppLifecycleListener(onResume: VibeBattery.refresh);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    VibeBattery.saving.removeListener(_changed);
    _timer?.cancel();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always the same widget shape: switching battery saver must never
    // rebuild the app underneath (that restarted the Matrix connection and
    // could stop notifications).
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: VibeBattery.saving.value
          ? mq.copyWith(disableAnimations: true)
          : mq,
      child: widget.child,
    );
  }
}

/// Settings > Appearance: the battery saver switches and slider.
class VibeBatterySettings extends StatefulWidget {
  const VibeBatterySettings({super.key});

  @override
  State<VibeBatterySettings> createState() => _VibeBatterySettingsState();
}

class _VibeBatterySettingsState extends State<VibeBatterySettings> {
  late int _at = AppSettings.vibeBatteryAutoAt.value;

  @override
  void initState() {
    super.initState();
    VibeBattery.saving.addListener(_changed);
    VibeBattery.refresh().then((_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    VibeBattery.saving.removeListener(_changed);
    super.dispose();
  }

  Future<void> _set(Future<void> Function() save) async {
    await save();
    await VibeBattery.refresh();
    _changed();
  }

  String get _status {
    if (!VibeBattery.saving.value) return 'Off';
    if (AppSettings.vibeBatterySaver.value) return 'On';
    if (AppSettings.vibeBatteryFollowPhone.value && VibeBattery.phoneSaver) {
      return 'On · phone battery saver';
    }
    return 'On · battery ${VibeBattery.level ?? '?'}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(
            'Battery saver',
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: Text(_status, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
        SwitchListTile.adaptive(
          title: const Text('Battery saver'),
          subtitle: const Text('Fewer animations, screen at 60 Hz'),
          value: AppSettings.vibeBatterySaver.value,
          onChanged: (v) => _set(() => AppSettings.vibeBatterySaver.setItem(v)),
        ),
        ListTile(
          title: const Text('Turn on automatically'),
          trailing: Text(
            _at == 0 ? 'Never' : 'at $_at%',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider.adaptive(
            min: 0,
            max: 50,
            divisions: 10,
            value: _at.toDouble(),
            label: _at == 0 ? 'Never' : '$_at%',
            onChanged: (d) => setState(() => _at = d.round()),
            onChangeEnd: (d) =>
                _set(() => AppSettings.vibeBatteryAutoAt.setItem(d.round())),
          ),
        ),
        SwitchListTile.adaptive(
          title: const Text('With the phone\'s battery saver'),
          subtitle: const Text('Turns on whenever your phone saves battery'),
          value: AppSettings.vibeBatteryFollowPhone.value,
          onChanged: (v) =>
              _set(() => AppSettings.vibeBatteryFollowPhone.setItem(v)),
        ),
      ],
    );
  }
}
