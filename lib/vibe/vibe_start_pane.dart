// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:vibe/vibe/vibe_add_contact.dart';
import 'package:vibe/vibe/vibe_communities.dart';
import 'package:vibe/vibe/vibe_dm_finder.dart';
import 'package:vibe/vibe/vibe_groups.dart';
import 'package:vibe/vibe/vibe_haptics.dart';
import 'package:vibe/vibe/vibe_motion.dart';
import 'package:vibe/vibe/vibe_public_rooms.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// The rail's "+", Discord style, in the middle pane: pick what to start
/// (a chat, a group, a community) from illustrated cards, join with an
/// invite link, or browse public groups and communities.
class VibeStartPane extends StatefulWidget {
  final VoidCallback onBack;
  const VibeStartPane({required this.onBack, super.key});

  @override
  State<VibeStartPane> createState() => _VibeStartPaneState();
}

class _Kind {
  final String title;
  final String text;
  final String image;
  final String action;
  const _Kind(this.title, this.text, this.image, this.action);
}

const _kinds = [
  _Kind(
    'Just the two of you',
    'A private chat with one person, end-to-end encrypted.',
    'assets/start/chat.png',
    'Start a chat',
  ),
  _Kind(
    'A group',
    'Friends, family or a team, all in one encrypted chat.',
    'assets/start/group.png',
    'Create a group',
  ),
  _Kind(
    'A community',
    'Several group chats (channels) in one place, for bigger crowds.',
    'assets/start/community.png',
    'Create a community',
  ),
];

class _VibeStartPaneState extends State<VibeStartPane> {
  final _cards = PageController(viewportFraction: 0.78);
  int _kind = 0;
  List<PublishedRoomsChunk>? _rooms;
  String? _joining;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cards.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Matrix.of(
        context,
      ).client.queryPublicRooms(limit: 12);
      if (mounted) setState(() => _rooms = res.chunk);
    } catch (_) {
      if (mounted) setState(() => _rooms = const []);
    }
  }

  void _start() {
    VibeHaptics.selection();
    switch (_kind) {
      case 0:
        VibeAddContact.show(context);
      case 1:
        VibeCreateGroupPage.open(context);
      default:
        VibeCreateGroupPage.open(context, community: true);
    }
  }

  Future<void> _openRoom(String roomId, {bool space = false}) async {
    final router = GoRouter.of(context);
    widget.onBack();
    if (space) {
      router.go('/rooms');
      VibeCommunities.select.value = roomId;
    } else {
      router.go('/rooms/$roomId');
    }
  }

  Future<void> _join(PublishedRoomsChunk r) async {
    final client = Matrix.of(context).client;
    final messenger = ScaffoldMessenger.of(context);
    final space = r.roomType == RoomCreationTypes.mSpace;
    final local = client.getRoomById(r.roomId);
    if (local == null || local.membership != Membership.join) {
      setState(() => _joining = r.roomId);
      try {
        if (r.joinRule == 'knock') {
          await client.knockRoom(r.roomId);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Asked to join. You\'ll get in once an admin '
                  'accepts.'),
            ),
          );
          if (mounted) setState(() => _joining = null);
          return;
        }
        await client.joinRoom(r.canonicalAlias ?? r.roomId);
        if (client.getRoomById(r.roomId) == null) {
          try {
            await client
                .waitForRoomInSync(r.roomId, join: true)
                .timeout(const Duration(seconds: 20));
          } on TimeoutException catch (_) {}
        }
        VibeHaptics.medium();
      } catch (e) {
        if (mounted) setState(() => _joining = null);
        messenger.showSnackBar(
          SnackBar(content: Text(e is MatrixException ? e.errorMessage : '$e')),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() => _joining = null);
    await _openRoom(r.roomId, space: space);
  }

  /// "I have an invite link": a matrix.to link, #group:server, a room ID
  /// or someone's @id.
  Future<void> _invite() async {
    final ctl = TextEditingController();
    final raw = await showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Join with an invite',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste an invite link, a group address or someone\'s ID',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctl,
              autofocus: true,
              autocorrect: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (v) => Navigator.pop(ctx, v),
              decoration: InputDecoration(
                hintText: 'https://matrix.to/#/#group:server',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Looks like https://matrix.to/#/#vibe:matrix.org, #vibe:matrix.org '
              'or @name:matrix.org',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
    ctl.dispose();
    final target = _parse(raw ?? '');
    if (target == null || !mounted) return;
    final client = Matrix.of(context).client;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (target.startsWith('@')) {
        final id = await VibeDmFinder.open(client, target);
        if (mounted) await _openRoom(id);
        return;
      }
      final roomId = await client.joinRoom(target);
      if (client.getRoomById(roomId) == null) {
        try {
          await client
              .waitForRoomInSync(roomId, join: true)
              .timeout(const Duration(seconds: 20));
        } on TimeoutException catch (_) {}
      }
      VibeHaptics.medium();
      if (mounted) {
        await _openRoom(
          roomId,
          space: client.getRoomById(roomId)?.isSpace ?? false,
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is MatrixException ? e.errorMessage : '$e')),
      );
    }
  }

  static String? _parse(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return null;
    try {
      v = Uri.decodeFull(v);
    } catch (_) {}
    final i = v.indexOf('#/');
    if (i >= 0) v = v.substring(i + 2);
    v = v.split('?').first.split('/').first;
    if (v.startsWith('#') || v.startsWith('!') || v.startsWith('@')) {
      return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rooms = _rooms;
    return Material(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                  ),
                  const Text(
                    'Start something',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Text(
                'Make a place for you and your people',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Chat one to one, gather a group, or build a whole community.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
            SizedBox(
              height: 236,
              child: PageView.builder(
                controller: _cards,
                padEnds: false,
                itemCount: _kinds.length,
                onPageChanged: (i) {
                  VibeHaptics.selection();
                  setState(() => _kind = i);
                },
                itemBuilder: (context, i) => Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 16 : 6, right: 6),
                  child: _KindCard(
                    kind: _kinds[i],
                    selected: i == _kind,
                    onTap: () {
                      if (i == _kind) return _start();
                      _cards.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _start,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    _kinds[_kind].action,
                    key: ValueKey(_kind),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: cs.surfaceContainerHigh,
                  foregroundColor: cs.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _invite,
                child: const Text(
                  'I have an invite link',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Join groups and communities',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => VibePublicRooms.show(context),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Public places on your server you might like.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
            if (rooms == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (rooms.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Nothing public here yet. Tap See all to look on other servers.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else
              for (var i = 0; i < rooms.length; i++)
                VibeStagger(
                  key: ValueKey('pub_${rooms[i].roomId}'),
                  index: i,
                  child: _PlaceCard(
                    room: rooms[i],
                    busy: _joining == rooms[i].roomId,
                    onJoin: () => _join(rooms[i]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  final _Kind kind;
  final bool selected;
  final VoidCallback onTap;
  const _KindCard({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return VibePressable(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: AnimatedScale(
                        scale: selected ? 1 : 0.9,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        child: Image.asset(kind.image, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kind.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    kind.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A public group or community: its picture as a blurred banner, the
/// picture itself on top, name, topic, members and Join.
class _PlaceCard extends StatelessWidget {
  final PublishedRoomsChunk room;
  final bool busy;
  final VoidCallback onJoin;
  const _PlaceCard({
    required this.room,
    required this.busy,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final client = Matrix.of(context).client;
    final r = room;
    final name = r.name ?? r.canonicalAlias ?? r.roomId;
    final joined =
        client.getRoomById(r.roomId)?.membership == Membership.join;
    final space = r.roomType == RoomCreationTypes.mSpace;
    final hue = (name.hashCode % 360).abs().toDouble();
    final avatar = r.avatarUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onJoin,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 112,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor(),
                            HSLColor.fromAHSL(1, (hue + 50) % 360, 0.6, 0.3)
                                .toColor(),
                          ],
                        ),
                      ),
                    ),
                    if (avatar != null)
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Opacity(
                          opacity: 0.85,
                          child: MxcImage(
                            client: client,
                            uri: avatar,
                            fit: BoxFit.cover,
                            width: 400,
                            height: 112,
                            isThumbnail: true,
                            cacheKey: 'vibe_place_banner_$avatar',
                          ),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      bottom: -26,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Avatar(
                          mxContent: avatar,
                          name: name,
                          size: 56,
                          client: client,
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 32, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          space ? Icons.workspaces : Icons.tag,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (r.topic != null && r.topic!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.topic!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: cs.onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${r.numJoinedMembers} members'
                          '${space ? ' · Community' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: busy ? null : onJoin,
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              joined
                                  ? 'Open'
                                  : r.joinRule == 'knock'
                                  ? 'Ask to join'
                                  : 'Join',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
  }
}
