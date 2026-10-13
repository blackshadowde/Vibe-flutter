// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/vibe/vibe_status.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Vibe privacy: hide online / last seen, and who sees your status and
/// local time.
abstract class VibePrivacy {
  static bool get hidePresence => AppSettings.vibeHidePresence.value;

  /// Presence to send with every sync. Hidden = always "offline", so the
  /// server never updates your online dot or last-seen time.
  static PresenceType? presenceFor({required bool resumed}) {
    if (hidePresence) return PresenceType.offline;
    return resumed ? null : PresenceType.unavailable;
  }

  static Future<void> setHidePresence(List<Client> clients, bool hide) async {
    await AppSettings.vibeHidePresence.setItem(hide);
    for (final c in clients) {
      if (!c.isLogged()) continue;
      c.syncPresence = hide ? PresenceType.offline : null;
      try {
        await c.setPresence(
          c.userID!,
          hide ? PresenceType.offline : PresenceType.online,
        );
      } catch (e) {
        Logs().d('Vibe privacy: could not set presence', e);
      }
    }
  }

  static String audienceLabel() =>
      switch (AppSettings.vibeStatusAudience.value) {
        'nobody' => 'Nobody',
        'picked' => 'People I pick',
        _ => 'Everyone I chat with',
      };
}

/// Settings > Security & sign-in: the two Vibe privacy rows.
class VibePrivacyTiles extends StatefulWidget {
  const VibePrivacyTiles({super.key});

  @override
  State<VibePrivacyTiles> createState() => _VibePrivacyTilesState();
}

class _VibePrivacyTilesState extends State<VibePrivacyTiles> {
  Future<void> _pickAudience() async {
    final client = Matrix.of(context).client;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Who can see my status and local time'),
        children: [
          for (final o in const [
            ('everyone', 'Everyone I chat with'),
            ('picked', 'Only people I pick'),
            ('nobody', 'Nobody'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(o.$1),
              child: Row(
                children: [
                  Icon(
                    AppSettings.vibeStatusAudience.value == o.$1
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(o.$2),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'picked') {
      final ok = await _pickPeople(client);
      if (!ok || !mounted) return;
    }
    await AppSettings.vibeStatusAudience.setItem(choice);
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    await VibeStatus.refresh(client);
    messenger.showSnackBar(
      SnackBar(content: Text('Status and local time: ${VibePrivacy.audienceLabel()}')),
    );
  }

  /// Checklist of the people you have direct chats with.
  Future<bool> _pickPeople(Client client) async {
    final people = <String, Room>{};
    for (final r in client.rooms) {
      final other = r.directChatMatrixID;
      if (r.isDirectChat && r.membership == Membership.join && other != null) {
        people[other] = r;
      }
    }
    final chosen = AppSettings.vibeStatusAllowed.value
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
    final result = await showVibeSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (ctx, scroll) => Column(
            children: [
              ListTile(
                title: const Text(
                  'Who can see my status and local time',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(chosen),
                  child: const Text('Done'),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  children: [
                    for (final e in people.entries)
                      CheckboxListTile(
                        value: chosen.contains(e.key),
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            chosen.add(e.key);
                          } else {
                            chosen.remove(e.key);
                          }
                        }),
                        secondary: Avatar(
                          mxContent: e.value.avatar,
                          name: e.value.getLocalizedDisplayname(),
                          size: 36,
                        ),
                        title: Text(e.value.getLocalizedDisplayname()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return false;
    await AppSettings.vibeStatusAllowed.setItem(result.join(','));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: const Text('Status and local time'),
          subtitle: Text(
            '${VibePrivacy.audienceLabel()}. People who can\'t see it see '
            'no status and not your time.',
          ),
          trailing: const Icon(Icons.chevron_right_outlined),
          onTap: _pickAudience,
        ),
        SwitchListTile.adaptive(
          value: VibePrivacy.hidePresence,
          title: const Text('Hide online and last seen'),
          subtitle: const Text(
            'Nobody sees when you\'re online or when you were last active.',
          ),
          onChanged: (hide) async {
            await VibePrivacy.setHidePresence(Matrix.of(context).widget.clients, hide);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}
