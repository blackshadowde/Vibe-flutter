// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_search/chat_search_files_tab.dart';
import 'package:fluffychat/pages/chat_search/chat_search_images_tab.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_starred.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

/// Starred messages / Media / Links / Files.
/// With [room] == null it shows starred messages of all chats.
class VibeSharedPage extends StatelessWidget {
  final Client client;
  final Room? room;

  const VibeSharedPage({required this.client, this.room, super.key});

  static void open(BuildContext context, Client client, {Room? room}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VibeSharedPage(client: client, room: room),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    final title = room == null
        ? 'Starred messages'
        : room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _StarredList(client: client, room: null),
      );
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Starred'),
              Tab(text: 'Media'),
              Tab(text: 'Links'),
              Tab(text: 'Files'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _StarredList(client: client, room: room),
            _PagedEvents(
              room: room,
              searchFunc: (event) => {
                MessageTypes.Image,
                MessageTypes.Video,
              }.contains(event.messageType),
              builder: (events, onMore, end, loading, until) =>
                  ChatSearchImagesTab(
                    room: room,
                    events: events,
                    onStartSearch: onMore,
                    endReached: end,
                    isLoading: loading,
                    searchedUntil: until,
                  ),
            ),
            _PagedEvents(
              room: room,
              searchFunc: (event) =>
                  event.type == EventTypes.Message &&
                  RegExp(r'https?://\S+').hasMatch(event.body),
              builder: (events, onMore, end, loading, until) =>
                  _LinksList(events: events, onMore: onMore, end: end),
            ),
            _PagedEvents(
              room: room,
              searchFunc: (event) =>
                  event.messageType == MessageTypes.File ||
                  (event.messageType == MessageTypes.Audio &&
                      !event.content.containsKey('org.matrix.msc3245.voice')),
              builder: (events, onMore, end, loading, until) =>
                  ChatSearchFilesTab(
                    room: room,
                    events: events,
                    onStartSearch: onMore,
                    endReached: end,
                    isLoading: loading,
                    searchedUntil: until,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PagedEvents extends StatefulWidget {
  final Room room;
  final bool Function(Event) searchFunc;
  final Widget Function(
    List<Event> events,
    void Function() onMore,
    bool endReached,
    bool isLoading,
    DateTime? searchedUntil,
  )
  builder;

  const _PagedEvents({
    required this.room,
    required this.searchFunc,
    required this.builder,
  });

  @override
  State<_PagedEvents> createState() => _PagedEventsState();
}

class _PagedEventsState extends State<_PagedEvents>
    with AutomaticKeepAliveClientMixin {
  final List<Event> events = [];
  String? nextBatch;
  bool endReached = false;
  bool isLoading = false;
  DateTime? searchedUntil;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (isLoading || endReached) return;
    setState(() => isLoading = true);
    try {
      final result = await widget.room.searchEvents(
        searchFunc: widget.searchFunc,
        nextBatch: nextBatch,
      );
      if (!mounted) return;
      setState(() {
        isLoading = false;
        events.addAll(result.events);
        nextBatch = result.nextBatch;
        endReached = result.nextBatch == null;
        searchedUntil = result.searchedUntil;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(events, _more, endReached, isLoading, searchedUntil);
  }
}

class _LinksList extends StatelessWidget {
  final List<Event> events;
  final void Function() onMore;
  final bool end;

  const _LinksList({
    required this.events,
    required this.onMore,
    required this.end,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final regex = RegExp(r'https?://\S+');
    final links = <(Event, String)>[];
    for (final e in events) {
      for (final m in regex.allMatches(e.body)) {
        links.add((e, m.group(0)!));
      }
    }
    return ListView.builder(
      itemCount: links.length + 1,
      itemBuilder: (context, i) {
        if (i == links.length) {
          if (end) {
            return links.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No links yet')),
                  )
                : const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: TextButton(
                onPressed: onMore,
                child: const Text('Load more'),
              ),
            ),
          );
        }
        final (event, url) = links[i];
        return ListTile(
          leading: Icon(Icons.link, color: theme.colorScheme.primary),
          title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(event.originServerTs.localizedTime(context)),
          onTap: () => launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ),
        );
      },
    );
  }
}

class _StarredList extends StatelessWidget {
  final Client client;
  final Room? room;

  const _StarredList({required this.client, required this.room});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: VibeStarred.revision,
      builder: (context, _, _) {
        final items = <(Room, String)>[];
        final rooms = room != null ? [room!] : client.rooms;
        for (final r in rooms) {
          for (final id in VibeStarred.ids(r.id)) {
            items.add((r, id));
          }
        }
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No starred messages yet.\nLong-press a message and tap the star.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final (r, id) = items[i];
            return FutureBuilder<Event?>(
              future: r.getEventById(id),
              builder: (context, snapshot) {
                final event = snapshot.data;
                if (event == null) {
                  return const ListTile(title: Text('…'));
                }
                final sender = event.senderFromMemoryOrFallback;
                final name = sender.calcDisplayname(
                  i18n: MatrixLocals(L10n.of(context)),
                );
                return ListTile(
                  leading: Avatar(
                    mxContent: sender.avatarUrl,
                    name: name,
                    size: 40,
                    client: client,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        event.originServerTs.localizedTimeShort(context),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    event.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.star, color: Theme.of(context).colorScheme.primary),
                    onPressed: () => VibeStarred.toggle(r.id, id),
                  ),
                  onTap: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.go('/rooms/${r.id}?event=$id');
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
