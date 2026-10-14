// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/vibe/vibe_communities.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// "Find public groups": the server's public directory, with search.
/// Groups open as chats; communities open in the community pane.
abstract class VibePublicRooms {
  static Future<void> show(BuildContext context) => showVibeSheet<void>(
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
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scroll) => _Browser(
        client: Matrix.of(context).client,
        scroll: scroll,
        router: GoRouter.of(context),
      ),
    ),
  );
}

class _Browser extends StatefulWidget {
  final Client client;
  final ScrollController scroll;
  final GoRouter router;
  const _Browser({
    required this.client,
    required this.scroll,
    required this.router,
  });

  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  final _search = TextEditingController();
  Timer? _debounce;
  late String _server = widget.client.userID?.domain ?? 'matrix.org';
  List<PublishedRoomsChunk>? _rooms;
  String? _next;
  bool _loadingMore = false;
  String? _error;
  String? _joining;
  int _query = 0;

  List<String> get _servers {
    final own = widget.client.userID?.domain;
    return {
      ?own,
      'matrix.org',
      'matrix.unredacted.org',
    }.toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final q = ++_query;
    final term = _search.text.trim();
    if (more) {
      if (_next == null || _loadingMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _rooms = null;
        _next = null;
        _error = null;
      });
    }
    try {
      final own = widget.client.userID?.domain;
      final res = await widget.client.queryPublicRooms(
        server: _server == own ? null : _server,
        filter: term.isEmpty
            ? null
            : PublicRoomQueryFilter(genericSearchTerm: term),
        limit: 30,
        since: more ? _next : null,
      );
      if (!mounted || q != _query) return;
      setState(() {
        _rooms = [...?(more ? _rooms : null), ...res.chunk];
        _next = res.nextBatch;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || q != _query) return;
      setState(() {
        _rooms ??= const [];
        _loadingMore = false;
        _error = e is MatrixException ? e.errorMessage : '$e';
      });
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _join(PublishedRoomsChunk r) async {
    final client = widget.client;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final isSpace = r.roomType == RoomCreationTypes.mSpace;
    final local = client.getRoomById(r.roomId);
    final own = client.userID?.domain;
    final via = _server == own ? null : [_server];
    if (local == null || local.membership != Membership.join) {
      setState(() => _joining = r.roomId);
      try {
        if (r.joinRule == 'knock') {
          await client.knockRoom(r.roomId, via: via);
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Asked to join. You\'ll get in once an admin '
                  'accepts.'),
            ),
          );
          if (mounted) setState(() => _joining = null);
          return;
        }
        await client.joinRoom(r.canonicalAlias ?? r.roomId, via: via);
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
          SnackBar(
            content: Text(e is MatrixException ? e.errorMessage : '$e'),
          ),
        );
        return;
      }
    }
    nav.pop();
    if (isSpace) {
      widget.router.go('/rooms');
      VibeCommunities.select.value = r.roomId;
    } else {
      widget.router.go('/rooms/${r.roomId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final card = VibeSettingsStyle.card(context);
    final rooms = _rooms;
    return CustomScrollView(
      controller: widget.scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: t2.withAlpha(0x66),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    Text('#', style: TextStyle(fontSize: 24, color: t2)),
                    const SizedBox(width: 12),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '|  ',
                            style: TextStyle(color: t2.withAlpha(0x88)),
                          ),
                          const TextSpan(text: 'public-groups'),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: t1,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 46,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 22, color: t2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: _onSearch,
                        onSubmitted: (_) => _load(),
                        textInputAction: TextInputAction.search,
                        style: TextStyle(color: t1, fontSize: 16),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search groups and communities',
                          hintStyle: TextStyle(color: t2, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final s in _servers)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(s),
                          selected: s == _server,
                          showCheckmark: false,
                          onSelected: (_) {
                            if (s == _server) return;
                            setState(() => _server = s);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
        if (rooms == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else if (rooms.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _error ??
                      (_search.text.trim().isEmpty
                          ? 'This server has no public groups yet.'
                          : 'Nothing found for “${_search.text.trim()}”'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t2),
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: rooms.length + (_next != null ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == rooms.length) {
                // reached the end: fetch the next page
                if (!_loadingMore) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _load(more: true),
                  );
                }
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                );
              }
              return _row(context, rooms[i]);
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _row(BuildContext context, PublishedRoomsChunk r) {
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final isSpace = r.roomType == RoomCreationTypes.mSpace;
    final name = r.name ?? r.canonicalAlias ?? r.roomId;
    final local = widget.client.getRoomById(r.roomId);
    final joined = local?.membership == Membership.join;
    final knock = r.joinRule == 'knock';
    return ListTile(
      key: ValueKey(r.roomId),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Avatar(
        mxContent: r.avatarUrl,
        name: name,
        size: 46,
        client: widget.client,
        borderRadius: isSpace ? BorderRadius.circular(14) : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t1, fontWeight: FontWeight.w600),
            ),
          ),
          if (isSpace) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: VibeSettingsStyle.card(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Community',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t2,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          '${r.numJoinedMembers} members',
          if (r.topic != null && r.topic!.trim().isNotEmpty) r.topic!.trim(),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t2, fontSize: 13),
      ),
      trailing: _joining == r.roomId
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _join(r),
              child: Text(
                joined
                    ? 'Open'
                    : knock
                    ? 'Ask'
                    : 'Join',
              ),
            ),
      onTap: () => _join(r),
    );
  }
}
