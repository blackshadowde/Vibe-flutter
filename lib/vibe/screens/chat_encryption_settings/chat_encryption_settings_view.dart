// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/app_config.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/chat_encryption_settings/chat_encryption_settings.dart';
import 'package:vibe/utils/beautify_string_extension.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_strict.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

const _green = Color(0xFF23A55A);
const _amber = Color(0xFFF0B232);
const _red = Color(0xFFDA373C);

/// Vibe's encryption page for a chat: what protects it, a switch to turn
/// encryption on, verify the other person, and everyone's devices.
class ChatEncryptionSettingsView extends StatelessWidget {
  final ChatEncryptionSettingsController controller;

  const ChatEncryptionSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    return VibeSettingsTheme(
      child: StreamBuilder<Object>(
        stream: room.client.onSync.stream.where(
          (s) => s.rooms?.join?[room.id] != null || s.deviceLists != null,
        ),
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/rooms/${controller.roomId!}'),
            ),
            title: const Text(
              'Encryption',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
          body: MaxWidthBody(
            child: FutureBuilder<List<User>>(
              future: room.encrypted
                  ? room.requestParticipants()
                  : Future.value(const <User>[]),
              builder: (context, snap) {
                final users = snap.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Summary(room: room, users: users),
                    VibeCard(
                      children: [
                        VibeSwitchRow(
                          title: L10n.of(context).encryptThisChat,
                          subtitle: room.encrypted
                              ? 'On for good — encryption can\'t be turned off'
                              : 'Only people in the chat can read new messages',
                          value: room.encrypted,
                          onChanged: room.encrypted
                              ? null
                              : controller.enableEncryption,
                        ),
                        if (room.encrypted)
                          VibeSwitchRow(
                            title: 'Strict encryption',
                            subtitle: VibeStrict.canChange(room)
                                ? 'A fresh key every ${VibeStrict.msgs} messages or '
                                      'every hour, so a leaked key unlocks '
                                      'only a few messages'
                                : 'Only people who can change this chat\'s '
                                      'settings can switch it',
                            value: VibeStrict.isOn(room),
                            onChanged: VibeStrict.canChange(room)
                                ? (on) async {
                                    VibeHaptics.medium();
                                    try {
                                      await VibeStrict.set(room, on);
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                    }
                                  }
                                : null,
                          ),
                      ],
                    ),
                    if (room.isDirectChat && room.encrypted)
                      _VerifyCard(controller: controller, room: room),
                    if (room.encrypted) ...[
                      const VibeSectionLabel('People and devices'),
                      if (users == null)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        )
                      else
                        VibeCard(
                          children: [
                            for (final u in users)
                              _Person(controller: controller, user: u),
                          ],
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              launchUrlString(AppConfig.encryptionTutorial),
                          icon: const Icon(Icons.help_outline, size: 18),
                          label: const Text('How encryption works'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Lock badge and one plain sentence about how safe this chat is.
class _Summary extends StatelessWidget {
  final Room room;
  final List<User>? users;
  const _Summary({required this.room, required this.users});

  @override
  Widget build(BuildContext context) {
    final keys = room.client.userDeviceKeys;
    final others = (users ?? const <User>[])
        .where((u) => u.id != room.client.userID)
        .toList();
    final allVerified =
        others.isNotEmpty &&
        others.every((u) => keys[u.id]?.masterKey?.verified == true);
    final Color color;
    final IconData icon;
    final String title;
    final String body;
    if (!room.encrypted) {
      color = _red;
      icon = Icons.lock_open;
      title = 'This chat isn\'t encrypted';
      body = 'The server can read these messages. Turn on encryption below.';
    } else if (allVerified) {
      color = _green;
      icon = Icons.lock;
      title = 'End-to-end encrypted and verified';
      body =
          'Only the people here can read these messages, and you\'ve '
          'confirmed it\'s really them.';
    } else {
      color = _amber;
      icon = Icons.lock;
      title = 'End-to-end encrypted';
      body =
          'Only the people here can read these messages — not even the '
          'server. Verify them to be sure no one is pretending.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(0x22),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: VibeSettingsStyle.text(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: VibeSettingsStyle.text2(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Verify Android Orb" with a small Verify button (DMs only).
class _VerifyCard extends StatelessWidget {
  final ChatEncryptionSettingsController controller;
  final Room room;
  const _VerifyCard({required this.controller, required this.room});

  @override
  Widget build(BuildContext context) {
    final otherId = room.directChatMatrixID;
    if (otherId == null) return const SizedBox.shrink();
    final other = room.unsafeGetUserFromMemoryOrFallback(otherId);
    final verified =
        room.client.userDeviceKeys[otherId]?.masterKey?.verified == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VibeSectionLabel('Verify'),
        VibeCard(
          children: [
            ListTile(
              leading: Avatar(
                mxContent: other.avatarUrl,
                name: other.calcDisplayname(),
                size: 36,
                client: room.client,
              ),
              title: Text(
                verified
                    ? '${other.calcDisplayname()} is verified'
                    : 'Verify ${other.calcDisplayname()}',
              ),
              subtitle: Text(
                verified
                    ? 'You compared emojis and they matched'
                    : 'Compare a few emojis on both phones to be sure '
                          'it\'s really them',
              ),
              trailing: verified
                  ? const Icon(Icons.verified_user, color: _green, size: 22)
                  : SizedBox(
                      height: 32,
                      child: FilledButton(
                        onPressed: controller.startVerification,
                        style: FilledButton.styleFrom(
                          backgroundColor: VibeSettingsStyle.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(fontFamily: 'Figtree', 
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Verify'),
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One person: picture, name, device count and trust; tap to see devices.
class _Person extends StatelessWidget {
  final ChatEncryptionSettingsController controller;
  final User user;
  const _Person({required this.controller, required this.user});

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final keys = room.client.userDeviceKeys[user.id];
    final master = keys?.masterKey;
    final devices = keys?.deviceKeys.values.toList() ?? const <DeviceKeys>[];
    final open = controller.uncollapsedUserId == user.id;
    final (String trust, Color trustColor, IconData trustIcon) = master == null
        ? ('No keys yet', VibeSettingsStyle.text2(context), Icons.help_outline)
        : master.verified
        ? ('Verified', _green, Icons.verified_user)
        : ('Not verified', _amber, Icons.gpp_maybe);
    final me = user.id == room.client.userID;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Avatar(
            mxContent: user.avatarUrl,
            name: user.calcDisplayname(),
            size: 36,
            client: room.client,
          ),
          title: Text(
            me ? '${user.calcDisplayname()} (you)' : user.calcDisplayname(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: devices.length == 1
                      ? '1 device · '
                      : '${devices.length} devices · ',
                ),
                TextSpan(
                  text: trust,
                  style: TextStyle(color: trustColor),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(trustIcon, size: 18, color: trustColor),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: VibeSettingsStyle.text2(context),
                ),
              ),
            ],
          ),
          onTap: () => controller.uncollapse(user.id),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: open
              ? Column(
                  children: [
                    for (final d in devices)
                      _Device(controller: controller, device: d),
                    if (devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(66, 0, 16, 12),
                        child: Text(
                          L10n.of(context).noUserKeyFound,
                          style: VibeSettingsStyle.rowSubtitle(context),
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Device extends StatelessWidget {
  final ChatEncryptionSettingsController controller;
  final DeviceKeys device;
  const _Device({required this.controller, required this.device});

  @override
  Widget build(BuildContext context) {
    final signed = device.hasValidSignatureChain(
      verifiedOnly: false,
      verifiedByTheirMasterKey: true,
    );
    final (String state, Color color) = device.verified
        ? ('Verified', _green)
        : device.blocked
        ? ('Blocked', _red)
        : signed
        ? ('Signed by them', VibeSettingsStyle.text2(context))
        : ('Unknown device', _amber);
    final name = device.deviceDisplayName?.isNotEmpty == true
        ? device.deviceDisplayName!
        : device.deviceId ?? 'Device';
    return Padding(
      padding: const EdgeInsets.fromLTRB(66, 0, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: VibeSettingsStyle.text(context),
                  ),
                ),
                Text(
                  state,
                  style: TextStyle(fontSize: 12.5, color: color),
                ),
                SelectableText(
                  device.curve25519Key?.beautified ??
                      L10n.of(context).noCurve25519KeyFound,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'RobotoMono',
                    color: VibeSettingsStyle.text2(context),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => controller.toggleBlocked(device),
            style: TextButton.styleFrom(
              foregroundColor: device.blocked
                  ? VibeSettingsStyle.text(context)
                  : _red,
              textStyle: const TextStyle(fontFamily: 'Figtree', 
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(device.blocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
  }
}
