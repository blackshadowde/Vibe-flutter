// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_add_contact.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart';
import 'package:fluffychat/vibe/vibe_user_sheet.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
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
    final name = await showDialog<String>(
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
    final ok = await showDialog<bool>(
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
}

// ---------------------------------------------------------------------------
// Create group
// ---------------------------------------------------------------------------

class VibeCreateGroupPage extends StatefulWidget {
  const VibeCreateGroupPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const VibeSettingsTheme(child: VibeCreateGroupPage()),
        ),
      );

  @override
  State<VibeCreateGroupPage> createState() => _VibeCreateGroupPageState();
}

class _VibeCreateGroupPageState extends State<VibeCreateGroupPage> {
  final _name = TextEditingController();
  final _id = TextEditingController();
  final Set<String> _picked = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
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

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name');
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
      final id = await client.createGroupChat(
        groupName: name,
        invite: _picked.toList(),
        enableEncryption: true,
        preset: CreateRoomPreset.privateChat,
      );
      VibeHaptics.medium();
      nav.pop();
      router.go('/rooms/$id');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create group')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: t1, fontSize: 17),
            decoration: deco('Group name', Icons.groups),
          ),
          const SizedBox(height: 8),
          Text(
            '🔒 End-to-end encrypted. Only the people in it can read it.',
            style: TextStyle(fontSize: 12.5, color: t2),
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
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _picked.isEmpty
                          ? 'Create group'
                          : 'Create group with ${_picked.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

  Future<void> _remove(User u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${u.calcDisplayname()}?'),
        content: const Text('They can be invited again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.room.kick(u.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final users = _users;
    final me = widget.room.client.userID;
    return CustomScrollView(
      controller: widget.scroll,
      slivers: [
        SliverToBoxAdapter(
          child: _SheetHeader(
            label: 'members',
            trailing: users == null ? null : '${users.length}',
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
                onLongPress: u.id != me && widget.room.canKick
                    ? () => _remove(u)
                    : null,
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
