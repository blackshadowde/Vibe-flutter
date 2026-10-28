// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/widgets/avatar.dart';

/// Discord-style tags next to names in groups: the person's role in this
/// group (Owner, Admin, Mod) and the group tag they picked (a short name of
/// one of their groups, with its picture).
///
/// The group tag travels in your own member event (`chat.vibe.tag`) in each
/// group you're in, which every member is allowed to change.
abstract class VibeMemberTags {
  static const key = 'chat.vibe.tag';

  /// "Wave Lovers" → "WAVE": the first word, letters and digits, 5 at most.
  static String tagFor(String name) {
    final word = name
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    final chars = word.toUpperCase().characters;
    return chars.take(5).toString();
  }

  static String? role(Room room, User user) {
    if (room.isDirectChat) return null;
    return switch (user.powerLevel.role) {
      PowerLevelRole.owner => 'Owner',
      PowerLevelRole.admin => 'Admin',
      PowerLevelRole.moderator => 'Mod',
      PowerLevelRole.user => null,
    };
  }

  static Map<String, Object?>? tagOf(Room room, String userId) {
    final t = room.getState(EventTypes.RoomMember, userId)?.content[key];
    if (t is! Map || t['tag'] is! String || (t['tag'] as String).isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(t);
  }

  static List<Room> _groups(Client client) => client.rooms
      .where((r) => r.membership == Membership.join && !r.isDirectChat)
      .toList();

  static Map<String, Object?>? _content(Client client) {
    final id = AppSettings.vibeGroupTag.value;
    if (id.isEmpty) return null;
    final room = client.getRoomById(id);
    if (room == null || room.membership != Membership.join) return null;
    final tag = tagFor(room.getLocalizedDisplayname());
    if (tag.isEmpty) return null;
    return {
      'tag': tag,
      'room': room.id,
      if (room.avatar != null) 'avatar': room.avatar.toString(),
    };
  }

  static bool _same(Object? a, Map<String, Object?>? b) {
    if (a is! Map) return b == null;
    if (b == null) return false;
    return a['tag'] == b['tag'] &&
        a['room'] == b['room'] &&
        a['avatar'] == b['avatar'];
  }

  /// Puts my picked tag (or removes it) in every group I'm in. Groups that
  /// already have it are skipped, so this is cheap to run again.
  static Future<void> sync(Client client) async {
    final me = client.userID;
    if (me == null) return;
    final tag = _content(client);
    final jobs = <Future<void> Function()>[];
    for (final r in _groups(client)) {
      final current = r.getState(EventTypes.RoomMember, me)?.content;
      if (current == null || current['membership'] != 'join') continue;
      if (_same(current[key], tag)) continue;
      final next = Map<String, Object?>.from(current);
      if (tag == null) {
        next.remove(key);
      } else {
        next[key] = tag;
      }
      jobs.add(() async {
        try {
          await client.setRoomStateWithKey(
            r.id,
            EventTypes.RoomMember,
            me,
            next,
          );
        } catch (e) {
          Logs().d('Vibe tag: could not set in ${r.id}', e);
        }
      });
    }
    for (var i = 0; i < jobs.length; i += 3) {
      await Future.wait(jobs.skip(i).take(3).map((j) => j()));
    }
  }

  /// Pick which group's tag shows next to my name.
  static Future<void> pick(BuildContext context, Client client) async {
    final groups = _groups(client)
      ..sort(
        (a, b) => a.getLocalizedDisplayname().toLowerCase().compareTo(
          b.getLocalizedDisplayname().toLowerCase(),
        ),
      );
    final current = AppSettings.vibeGroupTag.value;
    final picked = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Group tag',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Shown next to your name in your groups.',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              RadioGroup<String>(
                groupValue: current,
                onChanged: (v) => Navigator.of(ctx).pop(v),
                child: Column(
                  children: [
                    const RadioListTile<String>(
                      value: '',
                      title: Text('No tag'),
                    ),
                    for (final r in groups)
                      if (tagFor(r.getLocalizedDisplayname()).isNotEmpty)
                        RadioListTile<String>(
                          value: r.id,
                          title: Text(
                            r.getLocalizedDisplayname(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: VibeTagChip(
                            tag: tagFor(r.getLocalizedDisplayname()),
                            avatar: r.avatar,
                            client: client,
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await AppSettings.vibeGroupTag.setItem(picked);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            picked.isEmpty
                ? 'Group tag removed'
                : 'Group tag set. It shows in your groups in a moment.',
          ),
        ),
      );
    }
    await sync(client);
  }

  /// Role and tag chips for [user] in [room] (nothing in direct chats).
  static List<Widget> chips(Room room, User user) {
    if (room.isDirectChat) return const [];
    final r = role(room, user);
    final t = tagOf(room, user.id);
    return [
      if (r != null) VibeRoleChip(r),
      if (t != null)
        VibeTagChip(
          tag: t['tag'] as String,
          avatar: t['avatar'] is String
              ? Uri.tryParse(t['avatar'] as String)
              : null,
          client: room.client,
        ),
    ];
  }
}

class VibeRoleChip extends StatelessWidget {
  final String role;
  const VibeRoleChip(this.role, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (role) {
      'Owner' => const Color(0xFFF0B232),
      'Admin' => const Color(0xFFF23F43),
      _ => const Color(0xFF5865F2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: Color.lerp(color, cs.onSurface, 0.2),
        ),
      ),
    );
  }
}

class VibeTagChip extends StatelessWidget {
  final String tag;
  final Uri? avatar;
  final Client client;
  const VibeTagChip({
    required this.tag,
    required this.avatar,
    required this.client,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 2, 6, 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(
            mxContent: avatar,
            name: tag,
            size: 14,
            client: client,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(width: 4),
          Text(
            tag,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
