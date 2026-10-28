// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/vibe/vibe_palette.dart';
import 'package:vibe/vibe/vibe_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:vibe/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/vibe/vibe_add_contact.dart';
import 'package:vibe/vibe/vibe_communities.dart';
import 'package:vibe/vibe/vibe_public_rooms.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/vibe/vibe_user_sheet.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix.dart' as sdk show Visibility;
import 'package:share_plus/share_plus.dart';

/// Group chats: Matrix rooms that aren't direct chats. They show as
/// "servers" in the rail under your DMs, open the same Vibgram-style pane
/// (with members and invites), and are end-to-end encrypted by default.
abstract class VibeGroups {
  static bool isGroup(Room r) => !r.isDirectChat && !r.isSpace;

  static String nameOf(BuildContext context, Room r) =>
      r.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));

  /// People you have direct chats with: the quick list to add to a group.
  static List<(String, Room)> contacts(Client client) {
    final seen = <String>{};
    final out = <(String, Room)>[];
    for (final r in client.rooms) {
      final id = r.directChatMatrixID;
      if (!r.isDirectChat || r.membership != Membership.join || id == null) {
        continue;
      }
      if (seen.add(id)) out.add((id, r));
    }
    return out;
  }

  static int memberCount(Room r) =>
      r.summary.mJoinedMemberCount ?? r.getParticipants().length;

  /// Public: anyone can find it and join without an invite.
  static bool isPublic(Room r) => r.joinRules == JoinRules.public;

  /// "Weekend Plans!" -> "weekend-plans" (for #weekend-plans:server).
  static String slug(String name) => name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  static void _snack(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _nice(Object e) {
    if (e is MatrixException) {
      if (e.errcode == 'M_ROOM_IN_USE') {
        return 'That link name is taken, try another one';
      }
      return e.errorMessage;
    }
    return '$e';
  }

  static String _matrixId(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('@')) v = '@$v';
    return v;
  }

  // ---- the "+" at the bottom of the rail ----

  static Future<void> showNew(BuildContext context) {
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    return showVibeSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: VibeSettingsStyle.card(ctx),
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.person_add, color: t1),
                    title: Text('New chat', style: TextStyle(color: t1)),
                    subtitle: Text(
                      'Message someone by their Vibe ID',
                      style: TextStyle(color: t2),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      VibeAddContact.show(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.group_add, color: t1),
                    title: Text('Create group', style: TextStyle(color: t1)),
                    subtitle: Text(
                      'Chat with several people, end-to-end encrypted',
                      style: TextStyle(color: t2),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      VibeCreateGroupPage.open(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.workspaces, color: t1),
                    title: Text(
                      'Create community',
                      style: TextStyle(color: t1),
                    ),
                    subtitle: Text(
                      'Several group chats (channels) in one place',
                      style: TextStyle(color: t2),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      VibeCreateGroupPage.open(context, community: true);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.travel_explore, color: t1),
                    title: Text(
                      'Find public groups',
                      style: TextStyle(color: t1),
                    ),
                    subtitle: Text(
                      'Browse and join groups and communities',
                      style: TextStyle(color: t2),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      VibePublicRooms.show(context);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- members ----

  static Future<void> showMembers(BuildContext context, Room room) =>
      showVibeSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: VibeSettingsStyle.page(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.96,
          builder: (ctx, scroll) => _Members(room: room, scroll: scroll),
        ),
      );

  // ---- invite ----

  static Future<void> showInvite(BuildContext context, Room room) =>
      showVibeSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: VibeSettingsStyle.page(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.96,
          builder: (ctx, scroll) => _Invite(room: room, scroll: scroll),
        ),
      );

  // ---- rename / leave ----

  static Future<void> rename(BuildContext context, Room room) async {
    final ctrl = TextEditingController(text: nameOf(context, room));
    final name = await showVibeDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Group name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      await room.setName(name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  static Future<void> leave(BuildContext context, Room room) async {
    final name = nameOf(context, room);
    final ok = await showVibeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave $name?'),
        content: const Text(
          'You won\'t get its messages any more. Someone in the group can '
          'invite you back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Leave',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await room.leave();
      if (context.mounted) context.go('/rooms');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Admins can delete a group (or community): Matrix has no real delete,
  /// so everyone is removed, nobody can join any more, and it's forgotten.
  static bool canDelete(Room room) =>
      room.ownPowerLevel.level >= 100 && room.canKick;

  static Future<void> delete(BuildContext context, Room room) async {
    final name = nameOf(context, room);
    final kind = room.isSpace ? 'community' : 'group';
    final ok = await showVibeDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(
          'Everyone is removed from the $kind and nobody can join it again. '
          'This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final client = room.client;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final nav = Navigator.of(context, rootNavigator: true);
    showVibeDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator.adaptive()),
    );
    var failed = 0;
    try {
      try {
        await room.setJoinRules(JoinRules.invite);
        await client.setRoomVisibilityOnDirectory(
          room.id,
          visibility: sdk.Visibility.private,
        );
      } catch (_) {}
      final people = await room.requestParticipants([
        Membership.join,
        Membership.invite,
        Membership.knock,
      ]);
      for (final u in people) {
        if (u.id == client.userID) continue;
        try {
          await room.kick(u.id);
        } catch (_) {
          failed++;
        }
      }
      await room.leave();
      try {
        await room.forget();
      } catch (_) {}
    } catch (e) {
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    nav.pop();
    if (failed > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$failed people couldn\'t be removed (they have the same role '
            'as you).',
          ),
        ),
      );
    }
    router.go('/rooms');
  }
}


// ---------------------------------------------------------------------------
// Group picture, privacy, roles (shared by groups and communities)
// ---------------------------------------------------------------------------

abstract class VibeGroupEdit {
  /// Pick a new picture (camera / gallery) or remove the current one.
  static Future<void> changePicture(BuildContext context, Room room) async {
    final t1 = VibeSettingsStyle.text(context);
    final action = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Avatar(
                    mxContent: room.avatar,
                    name: VibeGroups.nameOf(ctx, room),
                    size: 44,
                    client: room.client,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    room.isSpace ? 'Community picture' : 'Group picture',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t1,
                    ),
                  ),
                ],
              ),
            ),
            _Card(
              children: [
                if (PlatformInfos.isMobile)
                  ListTile(
                    leading: Icon(Icons.photo_camera, color: t1),
                    title: Text('Take a photo', style: TextStyle(color: t1)),
                    onTap: () => Navigator.pop(ctx, 'camera'),
                  ),
                ListTile(
                  leading: Icon(Icons.photo_library, color: t1),
                  title: Text(
                    'Choose from gallery',
                    style: TextStyle(color: t1),
                  ),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                if (room.avatar != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    title: Text(
                      'Remove picture',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                    onTap: () => Navigator.pop(ctx, 'remove'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    try {
      if (action == 'remove') {
        await room.setAvatar(null);
        if (!context.mounted) return;
        VibeGroups._snack(context, 'Picture removed');
        return;
      }
      MatrixFile? file;
      if (PlatformInfos.isMobile) {
        final picked = await ImagePicker().pickImage(
          source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 82,
        );
        if (picked == null) return;
        file = MatrixImageFile(
          bytes: await picked.readAsBytes(),
          name: picked.name,
        );
      } else {
        if (!context.mounted) return;
        final picked = await selectFiles(context, type: FileType.image);
        if (picked.isEmpty) return;
        file = MatrixImageFile(
          bytes: await picked.first.readAsBytes(),
          name: picked.first.name,
        );
      }
      if (context.mounted) VibeGroups._snack(context, 'Uploading picture…');
      await room.setAvatar(file);
      VibeHaptics.light();
      if (context.mounted) VibeGroups._snack(context, 'Picture updated');
    } catch (e) {
      if (context.mounted) VibeGroups._snack(context, VibeGroups._nice(e));
    }
  }

  /// Private (invite / link only) or Public (anyone can find and join).
  static Future<void> privacy(BuildContext context, Room room) =>
      showVibeSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: VibeSettingsStyle.page(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => _Privacy(room: room),
      );

  /// Promote / demote / remove someone. Only offered when you outrank them.
  static Future<bool> manageMember(
    BuildContext context,
    Room room,
    User u,
  ) async {
    final me = room.ownPowerLevel.level;
    final them = u.powerLevel.level;
    final canRole = room.canChangePowerLevel && me > them;
    final canKick = room.canKick && me > them;
    if (!canRole && !canKick) return false;
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final role = u.powerLevel.role;
    final action = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Avatar(
                    mxContent: u.avatarUrl,
                    name: u.calcDisplayname(),
                    size: 44,
                    client: room.client,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.calcDisplayname(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: t1,
                          ),
                        ),
                        Text(
                          switch (role) {
                            PowerLevelRole.owner => 'Owner',
                            PowerLevelRole.admin => 'Admin',
                            PowerLevelRole.moderator => 'Moderator',
                            PowerLevelRole.user => 'Member',
                          },
                          style: TextStyle(color: t2, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _Card(
              children: [
                if (canRole && role != PowerLevelRole.admin && me >= 100)
                  ListTile(
                    leading: Icon(Icons.shield, color: t1),
                    title: Text('Make admin', style: TextStyle(color: t1)),
                    subtitle: Text(
                      'Can change everything, add admins and remove people',
                      style: TextStyle(color: t2),
                    ),
                    onTap: () => Navigator.pop(ctx, 'admin'),
                  ),
                if (canRole && role != PowerLevelRole.moderator && me >= 50)
                  ListTile(
                    leading: Icon(Icons.verified_user, color: t1),
                    title: Text('Make moderator', style: TextStyle(color: t1)),
                    subtitle: Text(
                      'Can remove people and delete messages',
                      style: TextStyle(color: t2),
                    ),
                    onTap: () => Navigator.pop(ctx, 'mod'),
                  ),
                if (canRole && role != PowerLevelRole.user)
                  ListTile(
                    leading: Icon(Icons.person, color: t1),
                    title: Text(
                      role == PowerLevelRole.admin
                          ? 'Remove admin'
                          : 'Remove moderator',
                      style: TextStyle(color: t1),
                    ),
                    onTap: () => Navigator.pop(ctx, 'user'),
                  ),
                if (canKick && u.membership != Membership.leave)
                  ListTile(
                    leading: Icon(
                      Icons.person_remove,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    title: Text(
                      u.membership == Membership.invite
                          ? 'Cancel invite'
                          : room.isSpace
                          ? 'Remove from community'
                          : 'Remove from group',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                    onTap: () => Navigator.pop(ctx, 'kick'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return false;
    final name = u.calcDisplayname();
    if (action == 'admin') {
      final ok = await showVibeDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Make $name an admin?'),
          content: const Text(
            'Admins have the same powers as you. On Matrix an admin can\'t '
            'be demoted by another admin, so only do this for people you '
            'trust.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Make admin'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return false;
    }
    if (action == 'kick') {
      final ok = await showVibeDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Remove $name?'),
          content: const Text('They can be invited again later.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Remove',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return false;
    }
    try {
      switch (action) {
        case 'admin':
          await room.setPower(u.id, PowerLevel.defaultAdminLevel);
          if (context.mounted) {
            VibeGroups._snack(context, '$name is now an admin');
          }
        case 'mod':
          await room.setPower(u.id, PowerLevel.defaultModeratorLevel);
          if (context.mounted) {
            VibeGroups._snack(context, '$name is now a moderator');
          }
        case 'user':
          await room.setPower(u.id, PowerLevel.defaultUserLevel);
          if (context.mounted) VibeGroups._snack(context, '$name is a member');
        case 'kick':
          await room.kick(u.id);
          if (context.mounted) VibeGroups._snack(context, 'Removed $name');
      }
      VibeHaptics.light();
      return true;
    } catch (e) {
      if (context.mounted) VibeGroups._snack(context, VibeGroups._nice(e));
      return false;
    }
  }
}

class _Privacy extends StatefulWidget {
  final Room room;
  const _Privacy({required this.room});

  @override
  State<_Privacy> createState() => _PrivacyState();
}

class _PrivacyState extends State<_Privacy> {
  late bool _public = VibeGroups.isPublic(widget.room);
  late final _link = TextEditingController(
    text: widget.room.canonicalAlias.isNotEmpty
        ? widget.room.canonicalAlias.localpart ?? ''
        : VibeGroups.slug(VibeGroups.nameOf(context, widget.room)),
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final room = widget.room;
    final client = room.client;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_public) {
        final slug = VibeGroups.slug(_link.text);
        if (slug.isEmpty) throw 'Pick a link name';
        final alias = '#$slug:${client.userID!.domain}';
        if (room.canonicalAlias != alias) {
          await client.setRoomAlias(alias, room.id);
          await room.setCanonicalAlias(alias);
        }
        await room.setJoinRules(JoinRules.public);
        if (room.canChangeHistoryVisibility) {
          await room.setHistoryVisibility(HistoryVisibility.shared);
        }
        await client.setRoomVisibilityOnDirectory(
          room.id,
          visibility: sdk.Visibility.public,
        );
      } else {
        await room.setJoinRules(JoinRules.invite);
        await client.setRoomVisibilityOnDirectory(
          room.id,
          visibility: sdk.Visibility.private,
        );
      }
      VibeHaptics.light();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = VibeGroups._nice(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final what = room.isSpace ? 'community' : 'group';
    final server = room.client.userID?.domain ?? '';
    final canEdit = room.canChangeJoinRules;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetTitle(label: 'privacy'),
            RadioGroup<bool>(
              groupValue: _public,
              onChanged: (v) {
                if (canEdit && v != null) setState(() => _public = v);
              },
              child: _Card(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    enabled: canEdit,
                    secondary: Icon(Icons.lock, color: t1),
                    title: Text('Private', style: TextStyle(color: t1)),
                    subtitle: Text(
                      'People join by invite or link',
                      style: TextStyle(color: t2),
                    ),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    enabled: canEdit,
                    secondary: Icon(Icons.public, color: t1),
                    title: Text('Public', style: TextStyle(color: t1)),
                    subtitle: Text(
                      'Anyone can find this $what and join',
                      style: TextStyle(color: t2),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: vibeSpring,
              child: _public
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _LinkField(
                        controller: _link,
                        server: server,
                        enabled: canEdit,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (_public && room.encrypted)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  'Messages stay end-to-end encrypted, but anyone who joins '
                  'can read new ones.',
                  style: TextStyle(fontSize: 12.5, color: t2),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (canEdit)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: _BlurpleButton(
                    busy: _busy,
                    label: 'Save',
                    onPressed: _save,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Only admins can change this.',
                  style: TextStyle(color: t2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkField extends StatelessWidget {
  final TextEditingController controller;
  final String server;
  final bool enabled;
  const _LinkField({
    required this.controller,
    required this.server,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      style: TextStyle(color: t1),
      decoration: InputDecoration(
        labelText: 'Public link',
        prefixText: '#',
        suffixText: ':$server',
        suffixStyle: TextStyle(color: t2),
        helperText: 'People can join with this link',
        helperStyle: TextStyle(color: t2),
        filled: true,
        fillColor: VibeSettingsStyle.card(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _BlurpleButton extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback onPressed;
  const _BlurpleButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: VibePalette.accent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    onPressed: busy ? null : onPressed,
    child: busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          )
        : Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
  );
}

/// Rounded card that groups list tiles.
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: VibeSettingsStyle.card(context),
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

/// "# | label" title for small sheets that already have a drag handle.
class _SheetTitle extends StatelessWidget {
  final String label;
  const _SheetTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    final muted = VibeSettingsStyle.text2(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Text('#', style: TextStyle(fontSize: 24, color: muted)),
          const SizedBox(width: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '|  ',
                  style: TextStyle(color: muted.withAlpha(0x88)),
                ),
                TextSpan(text: label),
              ],
            ),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: VibeSettingsStyle.text(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create group
// ---------------------------------------------------------------------------

class VibeCreateGroupPage extends StatefulWidget {
  /// A community (Matrix space) instead of a single group chat.
  final bool community;
  const VibeCreateGroupPage({this.community = false, super.key});

  static Future<void> open(BuildContext context, {bool community = false}) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => VibeSettingsTheme(
            child: VibeCreateGroupPage(community: community),
          ),
        ),
      );

  @override
  State<VibeCreateGroupPage> createState() => _VibeCreateGroupPageState();
}

class _VibeCreateGroupPageState extends State<VibeCreateGroupPage> {
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _link = TextEditingController();
  final Set<String> _picked = {};
  bool _public = false;
  bool _linkEdited = false;
  MatrixImageFile? _picture;
  bool _busy = false;
  String? _error;

  bool get _community => widget.community;
  String get _what => _community ? 'community' : 'group';

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (!_linkEdited) _link.text = VibeGroups.slug(_name.text);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _link.dispose();
    super.dispose();
  }

  void _addTyped() {
    final id = VibeGroups._matrixId(_id.text);
    if (!id.isValidMatrixId) {
      setState(() => _error = 'That doesn\'t look like a Vibe ID (@name:server)');
      return;
    }
    setState(() {
      _picked.add(id);
      _error = null;
      _id.clear();
    });
  }

  Future<void> _pickPicture() async {
    try {
      if (PlatformInfos.isMobile) {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 82,
        );
        if (picked == null) return;
        final file = MatrixImageFile(
          bytes: await picked.readAsBytes(),
          name: picked.name,
        );
        if (mounted) setState(() => _picture = file);
      } else {
        final picked = await selectFiles(context, type: FileType.image);
        if (picked.isEmpty) return;
        final file = MatrixImageFile(
          bytes: await picked.first.readAsBytes(),
          name: picked.first.name,
        );
        if (mounted) setState(() => _picture = file);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the $_what a name');
      return;
    }
    final slug = VibeGroups.slug(_link.text);
    if (_public && slug.isEmpty) {
      setState(() => _error = 'Pick a public link');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = Matrix.of(context).client;
    final router = GoRouter.of(context);
    final nav = Navigator.of(context);
    try {
      Uri? avatar;
      if (_picture != null) {
        avatar = await client.uploadContent(
          _picture!.bytes,
          filename: _picture!.name,
          contentType: _picture!.mimeType,
        );
      }
      final avatarState = [
        if (avatar != null)
          StateEvent(
            type: EventTypes.RoomAvatar,
            content: {'url': avatar.toString()},
          ),
      ];
      if (_community) {
        final id = await VibeCommunities.create(
          client,
          name: name,
          isPublic: _public,
          alias: _public ? slug : null,
          invite: _picked.toList(),
          initialState: avatarState,
        );
        VibeHaptics.medium();
        nav.pop();
        VibeCommunities.select.value = id;
        return;
      }
      final String id;
      if (_public) {
        id = await client.createRoom(
          name: name,
          preset: CreateRoomPreset.publicChat,
          visibility: sdk.Visibility.public,
          roomAliasName: slug,
          invite: _picked.toList(),
          initialState: avatarState,
        );
        await client.waitForRoomInSync(id, join: true);
      } else {
        id = await client.createGroupChat(
          groupName: name,
          invite: _picked.toList(),
          enableEncryption: true,
          preset: CreateRoomPreset.privateChat,
          initialState: avatarState,
        );
      }
      VibeHaptics.medium();
      nav.pop();
      router.go('/rooms/$id');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = VibeGroups._nice(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final contacts = VibeGroups.contacts(client);
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final card = VibeSettingsStyle.card(context);
    final extra = _picked
        .where((id) => !contacts.any((c) => c.$1 == id))
        .toList();
    InputDecoration deco(String hint, IconData icon) => InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: t2),
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
    final picture = _picture;
    return Scaffold(
      appBar: AppBar(
        title: Text(_community ? 'Create community' : 'Create group'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickPicture,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(_community ? 18 : 32),
                    image: picture == null
                        ? null
                        : DecorationImage(
                            image: MemoryImage(picture.bytes),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: picture == null
                      ? Icon(Icons.add_a_photo, color: t2)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: t1, fontSize: 17),
                  decoration: deco(
                    _community ? 'Community name' : 'Group name',
                    _community ? Icons.workspaces : Icons.groups,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RadioGroup<bool>(
            groupValue: _public,
            onChanged: (v) => setState(() => _public = v ?? false),
            child: Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      value: false,
                      secondary: Icon(Icons.lock, color: t1),
                      title: Text('Private', style: TextStyle(color: t1)),
                      subtitle: Text(
                        _community
                            ? 'Only people you invite can join'
                            : 'End-to-end encrypted, invite only',
                        style: TextStyle(color: t2),
                      ),
                    ),
                    RadioListTile<bool>(
                      value: true,
                      secondary: Icon(Icons.public, color: t1),
                      title: Text('Public', style: TextStyle(color: t1)),
                      subtitle: Text(
                        'Anyone can find it in Find public groups and join',
                        style: TextStyle(color: t2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: vibeSpring,
            child: _public
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Focus(
                      onFocusChange: (f) {
                        if (f) _linkEdited = true;
                      },
                      child: _LinkField(
                        controller: _link,
                        server: client.userID?.domain ?? '',
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (_community)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'A #general channel is created for you. Add more channels '
                'from the community pane.',
                style: TextStyle(fontSize: 12.5, color: t2),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'ADD PEOPLE${_picked.isEmpty ? '' : ' — ${_picked.length}'}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: t2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _id,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _addTyped(),
            style: TextStyle(color: t1),
            decoration: deco('@name:server', Icons.alternate_email).copyWith(
              suffixIcon: IconButton(
                icon: Icon(Icons.add_circle, color: t1),
                onPressed: _addTyped,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (final id in extra)
                    CheckboxListTile(
                      value: true,
                      onChanged: (_) => setState(() => _picked.remove(id)),
                      secondary: Avatar(name: id.localpart ?? id, size: 40),
                      title: Text(id, style: TextStyle(color: t1)),
                    ),
                  for (final c in contacts)
                    CheckboxListTile(
                      value: _picked.contains(c.$1),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _picked.add(c.$1);
                        } else {
                          _picked.remove(c.$1);
                        }
                      }),
                      secondary: Avatar(
                        mxContent: c.$2.avatar,
                        name: VibeGroups.nameOf(context, c.$2),
                        size: 40,
                        client: client,
                      ),
                      title: Text(
                        VibeGroups.nameOf(context, c.$2),
                        style: TextStyle(color: t1),
                      ),
                      subtitle: Text(c.$1, style: TextStyle(color: t2)),
                    ),
                  if (contacts.isEmpty && extra.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Type someone\'s Vibe ID above to add them. You can also '
                        'invite people later.',
                        style: TextStyle(color: t2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 54,
            child: _BlurpleButton(
              busy: _busy,
              onPressed: _create,
              label: _picked.isEmpty
                  ? 'Create $_what'
                  : 'Create $_what with ${_picked.length}',
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Members pane
// ---------------------------------------------------------------------------

class _Members extends StatefulWidget {
  final Room room;
  final ScrollController scroll;
  const _Members({required this.room, required this.scroll});

  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  List<User>? _users;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = (await widget.room.requestParticipants()).toList();
      int rank(User u) => switch (u.powerLevel.role) {
        PowerLevelRole.owner => 0,
        PowerLevelRole.admin => 1,
        PowerLevelRole.moderator => 2,
        PowerLevelRole.user => u.membership == Membership.invite ? 4 : 3,
      };
      users.sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.calcDisplayname().compareTo(b.calcDisplayname());
      });
      if (mounted) setState(() => _users = users);
    } catch (_) {
      if (mounted) setState(() => _users = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final all = _users;
    final q = _query.trim().toLowerCase();
    final users = all == null || q.isEmpty
        ? all
        : all
              .where(
                (u) =>
                    u.calcDisplayname().toLowerCase().contains(q) ||
                    u.id.toLowerCase().contains(q),
              )
              .toList();
    final me = widget.room.client.userID;
    return CustomScrollView(
      controller: widget.scroll,
      slivers: [
        SliverToBoxAdapter(
          child: _SheetHeader(
            label: 'members',
            trailing: all == null ? null : '${all.length}',
          ),
        ),
        if (all != null && all.length > 1)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search members',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: VibeSettingsStyle.card(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        if (widget.room.canChangePowerLevel || widget.room.canKick)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                'Long-press someone to make them an admin or remove them.',
                style: TextStyle(fontSize: 12.5, color: t2),
              ),
            ),
          ),
        if (users == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else
          SliverList.builder(
            itemCount: users.length,
            itemBuilder: (context, i) {
              final u = users[i];
              final role = switch (u.powerLevel.role) {
                PowerLevelRole.owner => 'Owner',
                PowerLevelRole.admin => 'Admin',
                PowerLevelRole.moderator => 'Mod',
                PowerLevelRole.user =>
                  u.membership == Membership.invite ? 'Invited' : null,
              };
              return ListTile(
                leading: Avatar(
                  mxContent: u.avatarUrl,
                  name: u.calcDisplayname(),
                  size: 40,
                  client: widget.room.client,
                  presenceUserId: u.id,
                ),
                title: Text(
                  u.id == me ? '${u.calcDisplayname()} (you)' : u.calcDisplayname(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t1, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(u.id, style: TextStyle(color: t2)),
                trailing: role == null
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: VibeSettingsStyle.card(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          role,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t2,
                          ),
                        ),
                      ),
                onTap: u.id == me
                    ? null
                    : () => VibeUserSheet.show(
                        context,
                        client: widget.room.client,
                        userId: u.id,
                        displayName: u.calcDisplayname(),
                        avatarUrl: u.avatarUrl,
                        currentRoomId: widget.room.id,
                      ),
                onLongPress: u.id == me
                    ? null
                    : () async {
                        final changed = await VibeGroupEdit.manageMember(
                          context,
                          widget.room,
                          u,
                        );
                        if (changed) {
                          // wait for the new power levels to sync back
                          await Future<void>.delayed(
                            const Duration(milliseconds: 700),
                          );
                          await _load();
                        }
                      },
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Invite pane
// ---------------------------------------------------------------------------

class _Invite extends StatefulWidget {
  final Room room;
  final ScrollController scroll;
  const _Invite({required this.room, required this.scroll});

  @override
  State<_Invite> createState() => _InviteState();
}

class _InviteState extends State<_Invite> {
  final _id = TextEditingController();
  final Set<String> _sent = {};
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _invite(String raw) async {
    final id = VibeGroups._matrixId(raw);
    if (!id.isValidMatrixId) {
      setState(() => _error = 'That doesn\'t look like a Vibe ID (@name:server)');
      return;
    }
    setState(() => _error = null);
    try {
      await widget.room.invite(id);
      VibeHaptics.light();
      if (mounted) {
        setState(() {
          _sent.add(id);
          _id.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final client = room.client;
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final members = room
        .getParticipants([Membership.join, Membership.invite])
        .map((u) => u.id)
        .toSet();
    final contacts = VibeGroups.contacts(
      client,
    ).where((c) => !members.contains(c.$1)).toList();
    final link = 'https://matrix.to/#/${room.canonicalAlias.isNotEmpty ? room.canonicalAlias : room.id}';
    return CustomScrollView(
      controller: widget.scroll,
      slivers: [
        const SliverToBoxAdapter(child: _SheetHeader(label: 'invite-people')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _id,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              onSubmitted: _invite,
              style: TextStyle(color: t1),
              decoration: InputDecoration(
                hintText: '@name:server',
                prefixIcon: Icon(Icons.alternate_email, color: t2),
                suffixIcon: IconButton(
                  icon: Icon(Icons.send, color: t1),
                  onPressed: () => _invite(_id.text),
                ),
                filled: true,
                fillColor: VibeSettingsStyle.card(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: ListTile(
            leading: Icon(Icons.link, color: t1),
            title: Text('Share invite link', style: TextStyle(color: t1)),
            subtitle: Text(
              'Anyone with the link can ask to join',
              style: TextStyle(color: t2),
            ),
            onTap: () => SharePlus.instance.share(
              ShareParams(text: 'Join ${VibeGroups.nameOf(context, room)} on Vibe: $link'),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: contacts.length,
          itemBuilder: (context, i) {
            final (id, dm) = contacts[i];
            final sent = _sent.contains(id);
            return ListTile(
              leading: Avatar(
                mxContent: dm.avatar,
                name: VibeGroups.nameOf(context, dm),
                size: 40,
                client: client,
              ),
              title: Text(
                VibeGroups.nameOf(context, dm),
                style: TextStyle(color: t1),
              ),
              subtitle: Text(id, style: TextStyle(color: t2)),
              trailing: FilledButton.tonal(
                onPressed: sent ? null : () => _invite(id),
                child: Text(sent ? 'Invited' : 'Invite'),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String label;
  final String? trailing;
  const _SheetHeader({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final muted = VibeSettingsStyle.text2(context);
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: muted.withAlpha(0x66),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              Text('#', style: TextStyle(fontSize: 24, color: muted)),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '|  ',
                      style: TextStyle(color: muted.withAlpha(0x88)),
                    ),
                    TextSpan(text: label),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
